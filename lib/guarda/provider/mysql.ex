defmodule Guarda.Provider.Mysql do
  @moduledoc """
  Provider worker for executing federated SQL queries securely against MySQL or MariaDB hosts.
  """
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
    db_name = Map.get(config, :database, "mysql")
    Logger.info("Initializing MySQL Provider actor for database: #{db_name}")

    opts = Map.to_list(config)

    case MyXQL.start_link(opts) do
      {:ok, pid} ->
        {:ok, Map.put(config, :pid, pid)}

      {:error, reason} ->
        Logger.error("Failed to connect to MySQL database: #{db_name}")
        {:error, reason}
    end
  end

  @impl Guarda.Provider
  def execute_query(sql_query, state) do
    Logger.info("Executing federated MySQL query: #{sql_query}")

    pid = state.pid

    try do
      result = MyXQL.query!(pid, sql_query, [])
      {:ok, %{status: 200, source: "mysql", data: %{columns: result.columns, rows: result.rows}}}
    rescue
      e ->
        Logger.error("MySQL query execution failed: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl Guarda.Provider
  def terminate_provider(state) do
    Logger.info("Terminating MySQL Provider actor (closing socket)")

    if pid = Map.get(state, :pid) do
      GenServer.stop(pid)
    end

    :ok
  end
end
