defmodule Guarda.AuditLog do
  @moduledoc """
  GenServer-backed query audit logger.

  Records every federated query execution with:
  - User identity
  - Provider type and config summary
  - Query text/filter
  - Timestamp and duration
  - Result status (success/error)

  Stores entries in an ETS table with periodic size management.
  """
  use GenServer
  require Logger

  @table_name :guarda_audit_log
  @max_entries 10_000

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Logs a query execution event.

  ## Parameters
    * `user` - User identifier (from auth claims)
    * `provider` - Provider type string (e.g., "postgres")
    * `query` - The query that was executed
    * `duration_ms` - Execution time in milliseconds
    * `status` - :ok or :error
    * `metadata` - Additional metadata map (optional)
  """
  def log_query(user, provider, query, duration_ms, status, metadata \\ %{}) do
    entry = %{
      id: System.unique_integer([:positive, :monotonic]),
      user: sanitize_user(user),
      provider: provider,
      query: truncate_query(query),
      duration_ms: duration_ms,
      status: status,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }

    GenServer.cast(__MODULE__, {:log, entry})
  end

  @doc "Returns the most recent `count` audit log entries."
  def recent(count \\ 50) do
    try do
      :ets.tab2list(@table_name)
      |> Enum.sort_by(& &1.id, :desc)
      |> Enum.take(count)
    rescue
      _ -> []
    end
  end

  @doc "Returns all audit log entries matching the given filters."
  def search(filters \\ %{}) do
    recent(1000)
    |> Enum.filter(fn entry ->
      Enum.all?(filters, fn
        {:user, user} -> entry.user == user
        {:provider, provider} -> entry.provider == provider
        {:status, status} -> entry.status == status
        {:since, since} -> DateTime.compare(entry.timestamp, since) != :lt
        _ -> true
      end)
    end)
  end

  @doc "Returns aggregate stats from the audit log."
  def stats do
    entries = recent(1000)

    %{
      total_queries: length(entries),
      by_provider: entries |> Enum.frequencies_by(& &1.provider),
      by_status: entries |> Enum.frequencies_by(& &1.status),
      avg_duration_ms:
        case entries do
          [] -> 0
          list -> list |> Enum.map(& &1.duration_ms) |> Enum.sum() |> div(length(list))
        end
    }
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_) do
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])
    Logger.info("Audit log initialized.")
    {:ok, %{count: 0}}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    :ets.insert(@table_name, {entry.id, entry})

    new_count = state.count + 1

    # Evict oldest entries when we exceed the limit
    if new_count > @max_entries do
      evict_oldest(div(@max_entries, 10))
      {:noreply, %{state | count: new_count - div(@max_entries, 10)}}
    else
      {:noreply, %{state | count: new_count}}
    end
  end

  # --- Private Helpers ---

  defp sanitize_user(user) when is_binary(user), do: user
  defp sanitize_user(user) when is_map(user), do: Map.get(user, "user_id", "unknown")
  defp sanitize_user(_), do: "unknown"

  defp truncate_query(query) when is_binary(query) do
    if String.length(query) > 500 do
      String.slice(query, 0, 500) <> "..."
    else
      query
    end
  end

  defp truncate_query(query), do: inspect(query, limit: 500)

  defp evict_oldest(count) do
    :ets.tab2list(@table_name)
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.take(count)
    |> Enum.each(fn {id, _} -> :ets.delete(@table_name, id) end)
  end
end
