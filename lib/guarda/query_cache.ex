defmodule Guarda.QueryCache do
  @moduledoc """
  ETS-based query result cache with configurable TTL and LRU eviction.

  Cache key is a hash of `{provider_type, query, params}`.
  Automatically evicts expired entries and enforces a maximum cache size.
  """
  use GenServer
  require Logger

  @table_name :guarda_query_cache
  @default_ttl_ms 60_000    # 60 seconds
  @max_cache_size 1_000
  @cleanup_interval 30_000  # 30 seconds

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Looks up a cached result for the given query key.

  Returns `{:ok, result}` on cache hit, `:miss` on cache miss or expired entry.
  """
  def get(provider, query, params \\ []) do
    key = cache_key(provider, query, params)

    try do
      case :ets.lookup(@table_name, key) do
        [{^key, %{expires_at: expires_at, result: result}}] ->
          if System.monotonic_time(:millisecond) < expires_at do
            GenServer.cast(__MODULE__, {:touch, key})
            {:ok, result}
          else
            GenServer.cast(__MODULE__, {:delete, key})
            :miss
          end

        [] ->
          :miss
      end
    rescue
      _ -> :miss
    end
  end

  @doc """
  Stores a query result in the cache.

  ## Options
    * `:ttl_ms` - Time-to-live in milliseconds (default: 60000)
  """
  def put(provider, query, params, result, opts \\ []) do
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    key = cache_key(provider, query, params)

    entry = %{
      result: result,
      expires_at: System.monotonic_time(:millisecond) + ttl_ms,
      last_accessed: System.monotonic_time(:millisecond),
      provider: provider,
      created_at: DateTime.utc_now()
    }

    GenServer.cast(__MODULE__, {:put, key, entry})
  end

  @doc "Invalidates all cache entries for a given provider."
  def invalidate(provider) do
    GenServer.cast(__MODULE__, {:invalidate_provider, provider})
  end

  @doc "Clears the entire cache."
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @doc "Returns cache statistics."
  def stats do
    try do
      size = :ets.info(@table_name, :size)
      %{entries: size || 0, max_size: @max_cache_size, ttl_ms: @default_ttl_ms}
    rescue
      _ -> %{entries: 0, max_size: @max_cache_size, ttl_ms: @default_ttl_ms}
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_) do
    :ets.new(@table_name, [:set, :public, :named_table,
      read_concurrency: true, write_concurrency: true])

    :timer.send_interval(@cleanup_interval, self(), :cleanup)
    Logger.info("Query cache initialized (max_size: #{@max_cache_size}, ttl: #{@default_ttl_ms}ms)")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put, key, entry}, state) do
    :ets.insert(@table_name, {key, entry})
    maybe_evict()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:touch, key}, state) do
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        updated = %{entry | last_accessed: System.monotonic_time(:millisecond)}
        :ets.insert(@table_name, {key, updated})
      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:delete, key}, state) do
    :ets.delete(@table_name, key)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:invalidate_provider, provider}, state) do
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_key, entry} -> entry.provider == provider end)
    |> Enum.each(fn {key, _} -> :ets.delete(@table_name, key) end)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table_name)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_key, entry} -> now >= entry.expires_at end)
    |> Enum.each(fn {key, _} -> :ets.delete(@table_name, key) end)

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp cache_key(provider, query, params) do
    :erlang.phash2({provider, query, params})
  end

  defp maybe_evict do
    size = :ets.info(@table_name, :size) || 0

    if size > @max_cache_size do
      # LRU eviction: remove the oldest-accessed 10%
      evict_count = div(@max_cache_size, 10)

      :ets.tab2list(@table_name)
      |> Enum.sort_by(fn {_key, entry} -> entry.last_accessed end)
      |> Enum.take(evict_count)
      |> Enum.each(fn {key, _} -> :ets.delete(@table_name, key) end)
    end
  end
end
