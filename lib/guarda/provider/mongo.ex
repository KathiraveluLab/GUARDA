defmodule Guarda.Provider.Mongo do
  @moduledoc """
  Provider worker for executing document queries natively against remote MongoDB registries.
  Unlike SQL providers, the query input here is typically expected to be a map/BSON filter.
  """
  use GenServer
  @behaviour Guarda.Provider

  require Logger

  @default_limit 1000
  @default_pool_size 5

  # Client API

  def start_link(config) do
    logical_name =
      cond do
        is_map(config) -> Map.get(config, :logical_name)
        is_list(config) -> Keyword.get(config, :logical_name)
        true -> nil
      end

    case logical_name do
      nil -> GenServer.start_link(__MODULE__, config)
      name ->
        meta = %{module: __MODULE__, started_at: DateTime.utc_now()}
        GenServer.start_link(__MODULE__, config, name: {:via, Registry, {Guarda.ProviderRegistry, name, meta}})
    end
  end

  def execute(pid, mongo_payload) do
    GenServer.call(pid, {:execute_query, mongo_payload})
  end

  # Server Callbacks

  @impl true
  def init(config) do
    case init_provider(config) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:execute_query, mongo_payload}, _from, state) do
    case execute_query(mongo_payload, state) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    terminate_provider(state)
  end

  # Provider Behaviour Implementation

  @impl Guarda.Provider
  def init_provider(config) do
    database = Map.get(config, :database, "admin")
    url = Map.get(config, :url, "mongodb://localhost:27017/#{database}")
    pool_size = Map.get(config, :pool_size, @default_pool_size)

    Logger.info("Initializing MongoDB Provider actor for URL: #{url}")

    # Use the returned pid directly instead of a hardcoded global name.
    # This prevents pool name conflicts when multiple Mongo providers are active.
    case Mongo.start_link(url: url, pool_size: pool_size) do
      {:ok, pid} ->
        {:ok, Map.put(config, :pid, pid)}

      {:error, reason} ->
        Logger.error("Failed to connect to MongoDB cluster.")
        {:error, reason}
    end
  end

  @impl Guarda.Provider
  def execute_query(mongo_payload, state) do
    collection = Map.get(mongo_payload, :collection, "records")
    filter = Map.get(mongo_payload, :filter, %{})
    limit = Map.get(mongo_payload, :limit, Map.get(state, :query_limit, @default_limit))

    Logger.info("Executing federated Mongo find on [#{collection}]: #{inspect(filter)} (limit: #{limit})")

    try do
      # Use the process pid from state instead of the hardcoded global pool name
      cursor = Mongo.find(state.pid, collection, filter, limit: limit)

      # Use Enum.take instead of Enum.to_list to prevent unbounded memory usage
      documents = Enum.take(cursor, limit)
      total_fetched = length(documents)
      truncated = total_fetched >= limit

      {:ok, %{
        status: 200,
        source: "mongodb",
        data: %{
          documents: documents,
          count: total_fetched,
          truncated: truncated,
          limit: limit
        }
      }}
    rescue
      e ->
        Logger.error("MongoDB execution failed: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl Guarda.Provider
  def terminate_provider(state) do
    Logger.info("Terminating MongoDB Provider actor pool.")

    if pid = Map.get(state, :pid) do
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end
end
