defmodule Guarda.ProviderSupervisor do
  @moduledoc """
  Manages dynamic data source provider actors. By running providers under a DynamicSupervisor,
  the gateway guarantees that if an individual database backend hangs or corrupts the socket stream,
  it only takes down its specific actor, instantly healing itself without collapsing the entire proxy.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Spawns a specific provider actor (e.g. Guarda.Provider.Http) under the application's DynamicSupervisor.
  """
  def start_provider(provider_module, config) do
    child_spec = %{
      id: make_ref(),
      start: {provider_module, :start_link, [config]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
