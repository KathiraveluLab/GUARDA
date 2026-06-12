defmodule GuardaWeb.QueryController do
  @moduledoc """
  Handles federated query execution via the REST API.

  Accepts a JSON payload specifying the provider type, connection config,
  and query to execute. Spawns a transient provider actor, runs the query,
  returns results, and cleans up.

  Integrates with:
  - `Guarda.QueryCache` for result caching
  - `Guarda.AuditLog` for query logging
  - `Guarda.HealthMonitor` for provider health tracking
  """
  use GuardaWeb, :controller

  require Logger

  @query_timeout 30_000
  @allowed_providers %{
    "postgres" => Guarda.Provider.Postgres,
    "mysql" => Guarda.Provider.Mysql,
    "mongo" => Guarda.Provider.Mongo,
    "mongodb" => Guarda.Provider.Mongo,
    "http" => Guarda.Provider.Http
  }

  @doc """
  POST /api/query

  Expects JSON body:
  ```json
  {
    "provider": "postgres" | "mysql" | "mongo" | "http",
    "config": { ... provider-specific connection config ... },
    "query": "SELECT ..." | { "collection": "...", "filter": {} },
    "params": [],
    "cache": true | false  // optional, defaults to true
  }
  ```
  """
  def execute(conn, params) do
    with {:ok, provider_type} <- validate_provider(params),
         {:ok, config} <- validate_config(params),
         {:ok, query} <- validate_query(params, provider_type),
         {:ok, provider_module} <- resolve_provider_module(provider_type) do
      # Check cache first (unless explicitly disabled)
      use_cache = Map.get(params, "cache", true)
      query_params = Map.get(params, "params", [])

      if use_cache do
        case Guarda.QueryCache.get(provider_type, query, query_params) do
          {:ok, cached_result} ->
            conn
            |> put_resp_header("x-cache", "HIT")
            |> put_status(:ok)
            |> json(%{status: "success", data: cached_result, cached: true})

          :miss ->
            execute_and_cache(conn, provider_module, provider_type, config, query, query_params)
        end
      else
        execute_fresh(conn, provider_module, provider_type, config, query, query_params)
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  # --- Validation ---

  defp validate_provider(%{"provider" => provider}) when is_binary(provider) do
    provider = String.downcase(provider)

    if Map.has_key?(@allowed_providers, provider) do
      {:ok, provider}
    else
      {:error, "Unknown provider '#{provider}'. Allowed: #{Map.keys(@allowed_providers) |> Enum.join(", ")}"}
    end
  end

  defp validate_provider(_), do: {:error, "Missing required field 'provider'"}

  defp validate_config(%{"config" => config}) when is_map(config) do
    {:ok, Guarda.ConfigHelper.safe_atomize_config(config)}
  end

  defp validate_config(_), do: {:error, "Missing or invalid 'config' field (must be a JSON object)"}

  defp validate_query(%{"query" => query}, provider_type) when is_binary(query) do
    if provider_type in ["postgres", "mysql"] do
      case safe_query?(query) do
        true -> {:ok, query}
        false -> {:error, "Only SELECT queries are allowed for SQL providers"}
      end
    else
      {:ok, query}
    end
  end

  defp validate_query(%{"query" => query}, _provider_type) when is_map(query) do
    atomized =
      Enum.reduce(query, %{}, fn
        {"collection", v}, acc -> Map.put(acc, :collection, v)
        {"filter", v}, acc -> Map.put(acc, :filter, v)
        {"limit", v}, acc -> Map.put(acc, :limit, v)
        {k, v}, acc when k in [:collection, :filter, :limit] -> Map.put(acc, k, v)
        _, acc -> acc
      end)

    {:ok, atomized}
  end

  defp validate_query(_, _), do: {:error, "Missing required field 'query'"}

  defp resolve_provider_module(provider_type) do
    case Map.get(@allowed_providers, provider_type) do
      nil -> {:error, "Provider module not found"}
      module -> {:ok, module}
    end
  end

  @doc """
  Checks that a SQL query is safe to execute (SELECT only).
  Rejects DDL, DML, and other potentially destructive statements.

  Note: This is a defense-in-depth measure. It may produce false positives
  when dangerous keywords appear inside string literals or comments (e.g.,
  `WHERE title LIKE '%create%'`). It does not guard against database-specific
  functions (e.g., `pg_read_file`, `LOAD_FILE`). Always enforce least-privilege
  permissions on the database user configured for each provider.
  """
  def safe_query?(sql) when is_binary(sql) do
    normalized = sql |> String.trim() |> String.upcase()

    # Must start with SELECT (or WITH for CTEs that resolve to SELECT)
    starts_with_select = String.starts_with?(normalized, "SELECT") or
                         String.starts_with?(normalized, "WITH")

    # Must not contain dangerous keywords
    dangerous_keywords = ~w(INSERT UPDATE DELETE DROP ALTER CREATE TRUNCATE EXEC EXECUTE GRANT REVOKE)

    has_dangerous =
      Enum.any?(dangerous_keywords, fn keyword ->
        Regex.match?(~r/\b#{keyword}\b/i, sql)
      end)

    starts_with_select and not has_dangerous
  end

  # --- Execution with caching ---

  defp execute_and_cache(conn, provider_module, provider_type, config, query, params) do
    case do_execute(conn, provider_module, provider_type, config, query, params) do
      {:ok, data} ->
        # Cache the successful result
        Guarda.QueryCache.put(provider_type, query, params, data)

        conn
        |> put_resp_header("x-cache", "MISS")
        |> put_status(:ok)
        |> json(%{status: "success", data: data, cached: false})

      {:error, status, body} ->
        conn |> put_status(status) |> json(body)
    end
  end

  defp execute_fresh(conn, provider_module, provider_type, config, query, params) do
    case do_execute(conn, provider_module, provider_type, config, query, params) do
      {:ok, data} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "success", data: data})

      {:error, status, body} ->
        conn |> put_status(status) |> json(body)
    end
  end

  defp do_execute(conn, provider_module, provider_type, config, query, params) do
    user = extract_user(conn)
    start_time = System.monotonic_time(:millisecond)

    case Guarda.ProviderSupervisor.start_provider(provider_module, config) do
      {:ok, pid} ->
        try do
          query_payload = build_query_payload(provider_module, query, params)
          result = GenServer.call(pid, {:execute_query, query_payload}, @query_timeout)
          duration = System.monotonic_time(:millisecond) - start_time

          case result do
            {:ok, data} ->
              Guarda.AuditLog.log_query(user, provider_type, inspect(query), duration, :ok)
              Guarda.HealthMonitor.record_query(provider_type, duration, :ok)
              {:ok, data}

            {:error, reason} ->
              Guarda.AuditLog.log_query(user, provider_type, inspect(query), duration, :error, %{reason: inspect(reason)})
              Guarda.HealthMonitor.record_query(provider_type, duration, :error)
              {:error, :unprocessable_entity, %{status: "error", error: inspect(reason)}}
          end
        catch
          :exit, {:timeout, _} ->
            duration = System.monotonic_time(:millisecond) - start_time
            Guarda.AuditLog.log_query(user, provider_type, inspect(query), duration, :error, %{reason: "timeout"})
            Guarda.HealthMonitor.record_query(provider_type, duration, :error)
            {:error, :gateway_timeout, %{status: "error", error: "Query timed out after #{div(@query_timeout, 1000)}s"}}

          kind, reason ->
            duration = System.monotonic_time(:millisecond) - start_time
            Logger.error("Query execution crashed: #{kind} - #{inspect(reason)}")
            Guarda.AuditLog.log_query(user, provider_type, inspect(query), duration, :error, %{reason: "crash"})
            Guarda.HealthMonitor.record_query(provider_type, duration, :error)
            {:error, :internal_server_error, %{status: "error", error: "Internal server error"}}
        after
          Guarda.ProviderSupervisor.stop_provider(pid)
        end

      {:error, :at_capacity} ->
        {:error, :service_unavailable, %{status: "error", error: "Server at capacity. Please retry later."}}

      {:error, reason} ->
        {:error, :bad_gateway, %{status: "error", error: "Failed to connect to provider: #{inspect(reason)}"}}
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

  # Extract the authenticated user identity from the connection (set by AuthPlug)
  defp extract_user(conn) do
    case Map.get(conn.assigns, :current_user) do
      nil -> "anonymous"
      user when is_binary(user) -> user
      user when is_map(user) -> Map.get(user, "user_id", Map.get(user, :user_id, "unknown"))
      _ -> "unknown"
    end
  end
end
