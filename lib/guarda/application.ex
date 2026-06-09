defmodule Guarda.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Create rate limit ETS table early to prevent concurrent request race conditions
    :ets.new(:guarda_rate_limits, [:bag, :public, :named_table, write_concurrency: true])

    children = [
      GuardaWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:guarda, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Guarda.PubSub},
      # Provider name registry for lookup by logical name
      {Registry, keys: :unique, name: Guarda.ProviderRegistry},
      # Task supervisor for async query execution
      {Task.Supervisor, name: Guarda.TaskSupervisor},
      # Core services
      Guarda.APIKeys,
      Guarda.AuditLog,
      Guarda.QueryCache,
      Guarda.HealthMonitor,
      Guarda.AsyncQuery,
      Guarda.ProviderSupervisor,
      # Start to serve requests, typically the last entry
      GuardaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Guarda.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    GuardaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
