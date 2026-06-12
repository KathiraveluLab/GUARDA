defmodule Guarda.Provider.Mysql do
  @moduledoc """
  Provider worker for executing federated SQL queries securely against MySQL or MariaDB hosts.
  """
  use GenServer
  @behaviour Guarda.Provider

  require Logger

  @default_pool_size 10

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

  @doc """
  Normalizes config to keyword list with atom keys.
  Handles string-keyed maps, atom-keyed maps, and keyword lists.
  Uses a whitelist of known config keys for safety.
  """
  def normalize_config(config) when is_list(config), do: config

  def normalize_config(config) when is_map(config) do
    known_keys = ~w(hostname username password database port pool_size ssl socket)

    Enum.reduce(config, [], fn
      {k, v}, acc when is_binary(k) ->
        if k in known_keys do
          [{String.to_existing_atom(k), v} | acc]
        else
          Logger.warning("Skipping unknown config key: #{k}")
          acc
        end

      {k, v}, acc when is_atom(k) ->
        [{k, v} | acc]

      _, acc ->
        acc
    end)
  end

  @impl Guarda.Provider
  def init_provider(config) do
    opts = normalize_config(config)

    # Add connection pooling if not specified
    opts =
      if Keyword.has_key?(opts, :pool_size) do
        opts
      else
        Keyword.put(opts, :pool_size, @default_pool_size)
      end

    db_name = Keyword.get(opts, :database, "mysql")
    Logger.info("Initializing MySQL Provider actor for database: #{db_name}")

    case MyXQL.start_link(opts) do
      {:ok, pid} ->
        {:ok, Enum.into(opts, %{pid: pid})}

      {:error, reason} ->
        Logger.error("Failed to connect to MySQL database: #{db_name}")
        {:error, reason}
    end
  end

  @impl Guarda.Provider
  def execute_query(sql_query, state) when is_binary(sql_query) do
    execute_query({sql_query, []}, state)
  end

  def execute_query({sql_template, params}, state) do
    Logger.info("Executing federated MySQL query: #{sql_template}")

    pid = state.pid

    try do
      result = MyXQL.query!(pid, sql_template, params)
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
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end
end
