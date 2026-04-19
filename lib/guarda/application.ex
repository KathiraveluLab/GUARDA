defmodule Guarda.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GuardaWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:guarda, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Guarda.PubSub},
      # Start a worker by calling: Guarda.Worker.start_link(arg)
      # {Guarda.Worker, arg},
      Guarda.APIKeys,
      Guarda.ProviderSupervisor,
      # Start to serve requests, typically the last entry
      GuardaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Guarda.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GuardaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
