defmodule Grana.ErrorTracker.Filter do
  @moduledoc """
  Sanitizes sensitive parameters and headers before ErrorTracker saves error occurrences.
  """
  @behaviour ErrorTracker.Filter

  @params ~w(request.params live_view.params live_view.event_params)

  @impl true
  def sanitize(context) do
    Map.new(context, fn
      {k, v} when k in @params and is_map(v) ->
        {k, Phoenix.Logger.filter_values(v)}

      {"request.headers", h} when is_map(h) ->
        {"request.headers", Map.drop(h, ["x-grana-webhook-secret"])}

      {"request.path", p} when is_binary(p) ->
        {"request.path",
         Regex.replace(~r{/(reset-password|confirm-email)/[^/]+}, p, "/\\1/[FILTERED]")}

      other ->
        other
    end)
  end
end
