defmodule Grana.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GranaWeb.Telemetry,
      Grana.Repo,
      {DNSCluster, query: Application.get_env(:grana, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Grana.PubSub},
      {Oban, Application.fetch_env!(:grana, Oban)},
      GranaWeb.Endpoint
    ]

    # Create ETS table for quote cache (owned by Application, survives process restarts)
    if :ets.whereis(:quote_cache) == :undefined do
      :ets.new(:quote_cache, [:set, :public, :named_table])
    end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Grana.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GranaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
