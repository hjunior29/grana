defmodule Grana.Analyses do
  @moduledoc """
  The AI analysis of a period shown on the dashboard: a month, or a whole year as month
  0. There is one per period, made by `Grana.Agents.Analyst` over the period's data
  (bank, source and movement filters do not apply) and kept until that data changes.
  It runs in the background through `Grana.Agents.Run`, under the name
  `{:analysis, year, month}`, so leaving the dashboard does not cancel it.
  """

  import Ecto.Query

  alias Grana.Agents.Analyst
  alias Grana.Agents.Run
  alias Grana.AI
  alias Grana.Banking.AIAnalysis
  alias Grana.Banking.Transaction
  alias Grana.Repo

  def subscribe(user_id), do: Run.subscribe(user_id)

  @doc "The newest analysis of the period, or nil."
  def latest(user_id, year, month) do
    AIAnalysis
    |> where([a], a.user_id == ^user_id and a.year == ^year and a.month == ^month)
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Whether transactions of the analysis' period were added or changed after it."
  def stale?(%AIAnalysis{} = analysis) do
    {from, to} = period_range(analysis.year, analysis.month)

    Repo.exists?(
      from(t in Transaction,
        where: t.user_id == ^analysis.user_id,
        where: t.date >= ^from and t.date <= ^to,
        where: t.updated_at > ^analysis.inserted_at
      )
    )
  end

  @doc """
  Analyzes the period in the background. When the latest analysis is still current (no
  data changed and the same model), nothing runs: `{:ok, :current}`. Otherwise
  `{:ok, :started}`, or `{:error, :busy}` while the period is already being analyzed.
  """
  def request(user_id, year, month, choice \\ nil) do
    analysis = latest(user_id, year, month)

    if analysis && !stale?(analysis) && same_model?(user_id, analysis, choice) do
      {:ok, :current}
    else
      user_id
      |> Run.start({:analysis, year, month}, nil, fn -> analyze(user_id, year, month, choice) end)
      |> case do
        {:ok, _pid} -> {:ok, :started}
        {:error, :busy} -> {:error, :busy}
      end
    end
  end

  @doc "The run of the period: `%{outcome:}` (nil while it runs), or nil when there is none."
  def in_progress(user_id, year, month), do: Run.current(user_id, {:analysis, year, month})

  def clear(user_id, year, month), do: Run.clear(user_id, {:analysis, year, month})

  defp same_model?(user_id, analysis, choice) do
    case AI.resolve(user_id, Analyst.key(), choice) do
      {:ok, config} -> config.model == analysis.ai_model
      {:error, _} -> true
    end
  end

  defp analyze(user_id, year, month, choice) do
    with {:ok, run} <- Analyst.run(user_id, %{year: year, month: month}, nil, choice) do
      %AIAnalysis{user_id: user_id}
      |> AIAnalysis.changeset(%{
        year: year,
        month: month,
        filters_json: %{year: year, month: month, context: "banking"},
        result_json: run.analysis,
        ai_provider: run.ai_provider,
        ai_model: run.ai_model
      })
      |> Repo.insert()
    end
  end

  defp period_range(year, 0), do: {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}

  defp period_range(year, month) do
    from = Date.new!(year, month, 1)
    {from, Date.end_of_month(from)}
  end
end
