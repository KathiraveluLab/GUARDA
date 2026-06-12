defmodule Guarda.AsyncQuery do
  @moduledoc """
  Async query manager with webhook callbacks.

  Accepts a query with a `callback_url`, executes it in a background Task,
  and POSTs the results to the callback URL on completion.
  Also provides status polling via query ID.
  """
  use GenServer
  require Logger

  @table_name :guarda_async_queries
  @cleanup_interval 300_000  # 5 minutes

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Submits a query for async execution.

  Returns `{:ok, query_id}` immediately. The query runs in the background
  and results are POSTed to `callback_url` when complete.
  """
  def submit(provider_module, provider_type, config, query, params, callback_url, user \\ "async") do
    query_id = generate_query_id()

    entry = %{
      id: query_id,
      status: :pending,
      provider: provider_type,
      query: query,
      callback_url: callback_url,
      user: user,
      submitted_at: DateTime.utc_now(),
      completed_at: nil,
      result: nil,
      error: nil
    }

    GenServer.call(__MODULE__, {:submit, query_id, entry, provider_module, config, params})
  end

  @doc "Gets the status of an async query by ID."
  def get_status(query_id) do
    case :ets.lookup(@table_name, query_id) do
      [{^query_id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @doc "Lists recent async queries."
  def list_recent(count \\ 20) do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, entry} -> entry end)
    |> Enum.sort_by(& &1.submitted_at, {:desc, DateTime})
    |> Enum.take(count)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    :timer.send_interval(@cleanup_interval, self(), :cleanup)
    Logger.info("Async query manager initialized.")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:submit, query_id, entry, provider_module, config, params}, _from, state) do
    :ets.insert(@table_name, {query_id, %{entry | status: :running}})

    # Execute query in a background Task
    Task.Supervisor.start_child(
      Guarda.TaskSupervisor,
      fn -> execute_async(query_id, provider_module, entry.provider, config, entry.query, params, entry.callback_url, entry.user) end
    )

    {:reply, {:ok, query_id}, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove completed queries older than 1 hour
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_id, entry} ->
      entry.status in [:completed, :failed] and
        entry.completed_at != nil and
        DateTime.compare(entry.completed_at, cutoff) == :lt
    end)
    |> Enum.each(fn {id, _} -> :ets.delete(@table_name, id) end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp execute_async(query_id, provider_module, provider_type, config, query, params, callback_url, user) do
    start_time = System.monotonic_time(:millisecond)

    result =
      case Guarda.ProviderSupervisor.start_provider(provider_module, config) do
        {:ok, pid} ->
          try do
            query_payload = build_query_payload(provider_module, query, params)
            GenServer.call(pid, {:execute_query, query_payload}, 60_000)
          catch
            :exit, {:timeout, _} -> {:error, "Query timed out"}
            kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
          after
            Guarda.ProviderSupervisor.stop_provider(pid)
          end

        {:error, reason} ->
          {:error, "Failed to start provider: #{inspect(reason)}"}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    # Update status in ETS
    case result do
      {:ok, data} ->
        update_status(query_id, :completed, data, nil)
        Guarda.AuditLog.log_query(user, provider_type, inspect(query), duration, :ok)
        deliver_webhook(callback_url, query_id, :completed, data)

      {:error, reason} ->
        update_status(query_id, :failed, nil, inspect(reason))
        Guarda.AuditLog.log_query(user, provider_type, inspect(query), duration, :error)
        deliver_webhook(callback_url, query_id, :failed, %{error: inspect(reason)})
    end
  end

  defp update_status(query_id, status, result, error) do
    case :ets.lookup(@table_name, query_id) do
      [{^query_id, entry}] ->
        updated = %{entry |
          status: status,
          result: result,
          error: error,
          completed_at: DateTime.utc_now()
        }
        :ets.insert(@table_name, {query_id, updated})
      _ ->
        :ok
    end
  end

  defp deliver_webhook(nil, _query_id, _status, _data), do: :ok
  defp deliver_webhook(callback_url, query_id, status, data) do
    case Jason.encode(%{
      query_id: query_id,
      status: to_string(status),
      data: data,
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }) do
      {:ok, payload} ->
        case Req.post(callback_url, body: payload, headers: [{"content-type", "application/json"}]) do
          {:ok, %{status: status_code}} when status_code in 200..299 ->
            Logger.info("Webhook delivered for query #{query_id}: #{status_code}")

          {:ok, %{status: status_code}} ->
            Logger.warning("Webhook delivery failed for query #{query_id}: HTTP #{status_code}")

          {:error, reason} ->
            Logger.error("Webhook delivery error for query #{query_id}: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error("Failed to encode webhook payload for query #{query_id}: #{inspect(reason)}")
    end
  end

  defp build_query_payload(module, query, params) when module in [Guarda.Provider.Postgres, Guarda.Provider.Mysql] do
    if params != [] do
      {query, params}
    else
      query
    end
  end

  defp build_query_payload(_module, query, _params), do: query

  defp generate_query_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
