defmodule Grana.Workers.AIAnalysisWorker do
  @moduledoc """
  Oban worker for AI-powered financial analysis via Gemini.
  """
  use Oban.Worker,
    queue: :ai_analysis,
    max_attempts: 2,
    unique: [
      period: 120,
      fields: [:worker, :args],
      keys: [:user_id, :context, :filters, :custom_prompt],
      states: Oban.Job.states() -- [:cancelled, :discarded, :completed]
    ]

  alias Grana.Banking
  alias Grana.Banking.AIAnalyzer

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{
          "user_id" => user_id,
          "context" => context,
          "filters" => filters,
          "custom_prompt" => custom_prompt,
          "topic" => topic
        }
      }) do
    filters = atomize_keys(filters)

    result =
      case context do
        "banking" ->
          AIAnalyzer.analyze_with_filters(user_id, filters, custom_prompt)

        "investments" ->
          AIAnalyzer.analyze_investments_with_filters(user_id, filters, custom_prompt)
      end

    case result do
      {:ok, analysis_result} ->
        filters_json = Map.put(filters, :context, context)

        {:ok, _analysis} =
          Banking.create_ai_analysis(%{
            user_id: user_id,
            prompt: custom_prompt,
            filters_json: filters_json,
            result_json: analysis_result
          })

        Oban.Job
        |> Grana.Repo.get(job_id)
        |> Ecto.Changeset.change(%{
          meta: %{"analysis" => analysis_result}
        })
        |> Grana.Repo.update()

        Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:analysis_complete, :ok})
        :ok

      {:error, msg} ->
        Oban.Job
        |> Grana.Repo.get(job_id)
        |> Ecto.Changeset.change(%{meta: %{"status" => "error", "error" => inspect(msg)}})
        |> Grana.Repo.update()

        Phoenix.PubSub.broadcast(Grana.PubSub, topic, {:analysis_complete, {:error, msg}})

        # Permanent failures (missing key, malformed model output) won't succeed on
        # retry — discard them so we don't burn the second attempt / extra API cost.
        # Transient failures (timeout, rate limit, 5xx) keep the normal retry path.
        if permanent_error?(msg) do
          {:discard, msg}
        else
          {:error, msg}
        end
    end
  end

  @permanent_markers ~w(api_key chave no_api_key json inválid invalid parse formato unauthorized 401 403)

  defp permanent_error?(msg) do
    text = msg |> to_string() |> String.downcase()
    Enum.any?(@permanent_markers, &String.contains?(text, &1))
  end

  @known_keys ~w(year month bank type statement_type institution_id asset_type)

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) and k in @known_keys -> {String.to_existing_atom(k), v}
      {k, v} when is_binary(k) -> {k, atomize_keys(v)}
      {k, v} -> {k, v}
    end)
  end

  defp atomize_keys(value), do: value
end
