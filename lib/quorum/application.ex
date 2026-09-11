defmodule Quorum.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_migrate()

    children =
      [
        QuorumWeb.Telemetry,
        Quorum.Repo,
        {DNSCluster, query: Application.get_env(:quorum, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Quorum.PubSub},
        Quorum.Contact.Limit,
        QuorumWeb.Presence,
        {Oban, Application.fetch_env!(:quorum, Oban)},
        heartbeat_child(),
        # Start to serve requests, typically the last entry
        QuorumWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Quorum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Migrations run in this node at boot when the release asks for it, rather than
  # in a separate `bin/migrate` node before it. One BEAM start instead of two,
  # which is a few seconds off every cold start. `Ecto.Migrator.with_repo` starts
  # and stops its own short-lived repo, so this runs before the supervision tree
  # brings up the app's own.
  defp maybe_migrate do
    if System.get_env("QUORUM_MIGRATE_ON_BOOT") == "true", do: Quorum.Release.migrate()
  end

  defp heartbeat_child do
    config = Application.get_env(:quorum, :heartbeat, [])
    if config[:enabled], do: {Quorum.Heartbeat, config}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QuorumWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
