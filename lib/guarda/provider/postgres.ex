defmodule Guarda.Provider.Postgres do
  use GenServer
  @behaviour Guarda.Provider

  require Logger

  # Client API

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def execute(pid, sql_query) do
    GenServer.call(pid, {:execute_query, sql_query})
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
  def handle_call({:execute_query, sql_query}, _from, state) do
    case execute_query(sql_query, state) do
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
    db_name = Map.get(config, :db_name, "postgres")
    Logger.info("Initializing Postgres Provider actor for DB: #{db_name}")

    case Postgrex.start_link(config) do
      {:ok, pid} ->
        {:ok, Map.put(config, :pid, pid)}

      {:error, reason} ->
        Logger.error("Failed to connect to Postgres DB: #{db_name}")
        {:error, reason}
    end
  end

  @impl Guarda.Provider
  def execute_query(sql_query, state) do
    Logger.info("Executing federated SQL query: #{sql_query}")

    pid = state.pid

    try do
      result = Postgrex.query!(pid, sql_query, [])

      {:ok,
       %{status: 200, source: "postgres", data: %{columns: result.columns, rows: result.rows}}}
    rescue
      e ->
        Logger.error("SQL execution failed: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl Guarda.Provider
  def terminate_provider(state) do
    Logger.info("Terminating Postgres Provider actor (closing socket)")

    if pid = Map.get(state, :pid) do
      GenServer.stop(pid)
    end

    :ok
  end
end
