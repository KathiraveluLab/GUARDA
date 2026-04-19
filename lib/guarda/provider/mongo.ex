defmodule Guarda.Provider.Mongo do
  @moduledoc """
  Provider worker for executing document queries natively against remote MongoDB registries.
  Unlike SQL providers, the query input here is typically expected to be a map/BSON filter.
  """
  use GenServer
  @behaviour Guarda.Provider

  require Logger

  # Client API

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
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
    
    Logger.info("Initializing MongoDB Provider actor for URL: #{url}")
    
    # Establish persistent pooling to the NoSQL registry
    case Mongo.start_link(url: url, name: :mongo_guarda_pool) do
      {:ok, pid} ->
        {:ok, Map.put(config, :pid, pid)}
      {:error, reason} ->
        Logger.error("Failed to connect to MongoDB cluster.")
        {:error, reason}
    end
  end

  @impl Guarda.Provider
  def execute_query(mongo_payload, _state) do
    collection = Map.get(mongo_payload, :collection, "records")
    filter = Map.get(mongo_payload, :filter, %{})
    
    Logger.info("Executing federated Mongo find on [#{collection}]: #{inspect(filter)}")
    
    try do
      # We route to the explicitly named Mongo connection pool
      cursor = Mongo.find(:mongo_guarda_pool, collection, filter)
      documents = Enum.to_list(cursor)
      
      {:ok, %{status: 200, source: "mongodb", data: %{documents: documents}}}
    rescue
      e ->
        Logger.error("MongoDB execution failed: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl Guarda.Provider
  def terminate_provider(_state) do
    Logger.info("Terminating MongoDB Provider actor pool.")
    :ok
  end
end
