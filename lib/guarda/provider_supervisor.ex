defmodule Guarda.ProviderSupervisor do
  @moduledoc """
  Manages dynamic data source provider actors. By running providers under a DynamicSupervisor,
  the gateway guarantees that if an individual database backend hangs or corrupts the socket stream,
  it only takes down its specific actor, instantly healing itself without collapsing the entire proxy.
  """
  use DynamicSupervisor

  @max_children Application.compile_env(:guarda, :max_providers, 100)

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: @max_children)
  end

  @doc """
  Spawns a specific provider actor (e.g. Guarda.Provider.Http) under the application's DynamicSupervisor.
  Returns `{:error, :at_capacity}` when the maximum number of providers is reached.

  ## Options
    * `:name` - Optional logical name for the provider (e.g., "main_postgres").
                Registers the provider in `Guarda.ProviderRegistry` for name-based lookup.
  """
  def start_provider(provider_module, config, opts \\ []) do
    logical_name = Keyword.get(opts, :name)

    # Inject logical_name into config for via tuple registration
    config = if logical_name, do: Map.put(config, :logical_name, logical_name), else: config

    child_spec = %{
      id: make_ref(),
      start: {provider_module, :start_link, [config]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        # Broadcast dashboard update
        GuardaWeb.DashboardLive.broadcast_refresh()
        {:ok, pid}

      {:error, :max_children} ->
        {:error, :at_capacity}

      error ->
        error
    end
  end

  @doc """
  Stops a running provider. Handles the case where the provider is already dead.
  """
  def stop_provider(pid) do
    result =
      case DynamicSupervisor.terminate_child(__MODULE__, pid) do
        :ok -> :ok
        {:error, :not_found} -> {:error, :not_found}
      end

    GuardaWeb.DashboardLive.broadcast_refresh()
    result
  end

  @doc """
  Looks up a provider by its logical name.
  Returns `{:ok, %{pid: pid, module: module}}` or `{:error, :not_found}`.
  """
  def lookup_provider(name) do
    case Registry.lookup(Guarda.ProviderRegistry, name) do
      [{pid, info}] when is_map(info) -> {:ok, Map.put(info, :pid, pid)}
      [{pid, _info}] -> {:ok, %{pid: pid}}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all registered providers with their names and metadata.
  """
  def list_providers do
    # Registry format: {name, pid, value}
    # Select all unique keys and values from registry
    Registry.select(Guarda.ProviderRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.map(fn
      {name, pid, info} when is_map(info) ->
        Map.merge(info, %{name: name, pid: pid, alive: Process.alive?(pid)})
      {name, pid, _} ->
        %{name: name, pid: pid, alive: Process.alive?(pid)}
    end)
  end
end
