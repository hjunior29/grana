defmodule Grana.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Cache em memória (só quando habilitado — ver Grana.Cache).
    children =
      [
        GranaWeb.Telemetry,
        Grana.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:grana, :ecto_repos), skip: skip_migrations?()}
      ] ++
        List.wrap(Grana.Cache.child_spec_or_nil()) ++
        [
          {Phoenix.PubSub, name: Grana.PubSub},
          {Task.Supervisor, name: Grana.TaskSupervisor},
          {Oban, Application.fetch_env!(:grana, Oban)},
          {Registry, keys: :unique, name: Grana.Chat.ReplyRegistry},
          {Task.Supervisor, name: Grana.Chat.TaskSupervisor},
          {DynamicSupervisor, name: Grana.Chat.ReplySupervisor, strategy: :one_for_one},
          {Registry, keys: :unique, name: Grana.Agents.RunRegistry},
          {Task.Supervisor, name: Grana.Agents.TaskSupervisor},
          {DynamicSupervisor, name: Grana.Agents.RunSupervisor, strategy: :one_for_one},
          Grana.Setup,
          Grana.Demo.Sessions
        ] ++
        demo_boot() ++
        [GranaWeb.Endpoint] ++ announce_setup()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Grana.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp demo_boot, do: if(Grana.Demo.enabled?(), do: [Grana.Demo.Boot], else: [])

  defp announce_setup do
    if Application.get_env(:grana, :announce_setup_code, true) do
      [{Task, &Grana.Setup.announce_if_setup_required/0}]
    else
      []
    end
  end

  # Só em release (RELEASE_NAME); em dev/test as migrations rodam via mix.
  defp skip_migrations? do
    System.get_env("SKIP_MIGRATIONS") == "true" or System.get_env("RELEASE_NAME") == nil
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GranaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
