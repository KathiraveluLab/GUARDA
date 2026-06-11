defmodule GuardaWeb.RateLimitPlug do
  @moduledoc """
  ETS-based rate limiting plug.

  Limits API requests to a configurable number per time window per client IP.
  Returns HTTP 429 (Too Many Requests) when the limit is exceeded.
  """
  import Plug.Conn
  require Logger

  @default_limit 60
  @default_window_ms 60_000
  @table_name :guarda_rate_limits

  def init(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)
    %{limit: limit, window_ms: window_ms}
  end

  def call(conn, %{limit: limit, window_ms: window_ms}) do
    ensure_table_exists()

    client_key = client_identifier(conn)
    now = System.monotonic_time(:millisecond)
    window_start = now - window_ms

    # Clean up expired entries and count current window
    cleanup_expired(client_key, window_start)
    count = count_requests(client_key, window_start)

    if count >= limit do
      Logger.warning("Rate limit exceeded for #{inspect(client_key)}")

      conn
      |> put_resp_header("retry-after", to_string(div(window_ms, 1000)))
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{error: "Too Many Requests", retry_after_seconds: div(window_ms, 1000)}))
      |> halt()
    else
      record_request(client_key, now)
      conn
    end
  end

  defp ensure_table_exists do
    case :ets.info(@table_name) do
      :undefined ->
        try do
          :ets.new(@table_name, [:bag, :public, :named_table, write_concurrency: true])
        rescue
          ArgumentError -> :ok
        end
      _ ->
        :ok
    end
  end

  defp client_identifier(conn) do
    # Use X-Forwarded-For if behind a proxy, otherwise use remote_ip
    forwarded = get_req_header(conn, "x-forwarded-for") |> List.first()

    if forwarded do
      forwarded |> String.split(",") |> List.first() |> String.trim()
    else
      conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp record_request(client_key, timestamp) do
    :ets.insert(@table_name, {client_key, timestamp})
  end

  defp count_requests(client_key, window_start) do
    # Count entries for this key that are within the current window
    :ets.select_count(@table_name, [
      {{client_key, :"$1"}, [{:>=, :"$1", window_start}], [true]}
    ])
  end

  defp cleanup_expired(client_key, window_start) do
    # Delete entries older than the window for the current client
    :ets.select_delete(@table_name, [
      {{client_key, :"$1"}, [{:<, :"$1", window_start}], [true]}
    ])

    # Periodically sweep all expired entries to prevent memory leaks from inactive clients.
    # Runs roughly once every 100 requests to amortize cost.
    if :rand.uniform(100) == 1 do
      :ets.select_delete(@table_name, [
        {{:_, :"$1"}, [{:<, :"$1", window_start}], [true]}
      ])
    end
  end
end
