defmodule GuardaWeb.StreamController do
  @moduledoc """
  Streaming query results as newline-delimited JSON (NDJSON).
  Uses chunked transfer encoding for large result sets.
  """
  use GuardaWeb, :controller
  require Logger

  @allowed_providers %{
    "postgres" => Guarda.Provider.Postgres,
    "mysql" => Guarda.Provider.Mysql,
    "mongo" => Guarda.Provider.Mongo,
    "mongodb" => Guarda.Provider.Mongo
  }

  @doc "POST /api/query/stream — streams results as NDJSON"
  def stream(conn, params) do
    with {:ok, provider_type} <- validate_provider(params),
         {:ok, config} <- validate_config(params),
         {:ok, query} <- validate_query(params),
         {:ok, module} <- resolve_module(provider_type) do
      stream_results(conn, module, provider_type, config, query, params)
    else
      {:error, msg} -> conn |> put_status(:bad_request) |> json(%{error: msg})
    end
  end

  defp stream_results(conn, module, _provider_type, config, query, params) do
    batch_size = Map.get(params, "batch_size", "100") |> to_integer()

    case Guarda.ProviderSupervisor.start_provider(module, config) do
      {:ok, pid} ->
        conn = conn
          |> put_resp_content_type("application/x-ndjson")
          |> put_resp_header("transfer-encoding", "chunked")
          |> send_chunked(200)

        try do
          query_payload = if Map.get(params, "params", []) != [] do
            {query, Map.get(params, "params", [])}
          else
            query
          end

          result = GenServer.call(pid, {:execute_query, query_payload}, 60_000)

          case result do
            {:ok, %{data: %{columns: columns, rows: rows}}} ->
              # Stream header
              {:ok, conn} = chunk(conn, Jason.encode!(%{type: "header", columns: columns}) <> "\n")

              # Stream rows in batches
              rows
              |> Enum.chunk_every(batch_size)
              |> Enum.reduce(conn, fn batch, conn ->
                line = Jason.encode!(%{type: "data", rows: batch}) <> "\n"
                case chunk(conn, line) do
                  {:ok, conn} -> conn
                  {:error, _} -> conn
                end
              end)

              # Stream footer
              chunk(conn, Jason.encode!(%{type: "footer", total: length(rows)}) <> "\n")
              conn

            {:ok, %{data: %{documents: docs}}} ->
              # MongoDB results
              docs
              |> Enum.chunk_every(batch_size)
              |> Enum.reduce(conn, fn batch, conn ->
                line = Jason.encode!(%{type: "data", documents: batch}) <> "\n"
                case chunk(conn, line) do
                  {:ok, conn} -> conn
                  {:error, _} -> conn
                end
              end)

              chunk(conn, Jason.encode!(%{type: "footer", total: length(docs)}) <> "\n")
              conn

            {:error, reason} ->
              chunk(conn, Jason.encode!(%{type: "error", error: inspect(reason)}) <> "\n")
              conn
          end
        after
          Guarda.ProviderSupervisor.stop_provider(pid)
        end

      {:error, :at_capacity} ->
        conn |> put_status(503) |> json(%{error: "At capacity"})

      {:error, reason} ->
        conn |> put_status(502) |> json(%{error: inspect(reason)})
    end
  end

  defp validate_provider(%{"provider" => p}) when is_binary(p) do
    p = String.downcase(p)
    if Map.has_key?(@allowed_providers, p), do: {:ok, p}, else: {:error, "Unknown provider"}
  end
  defp validate_provider(_), do: {:error, "Missing 'provider'"}

  defp validate_config(%{"config" => c}) when is_map(c) do
    {:ok, Guarda.ConfigHelper.safe_atomize_config(c)}
  end
  defp validate_config(_), do: {:error, "Missing 'config'"}

  defp validate_query(%{"query" => q}), do: {:ok, q}
  defp validate_query(_), do: {:error, "Missing 'query'"}

  defp resolve_module(type), do: {:ok, Map.get(@allowed_providers, type)}

  defp to_integer(v) when is_integer(v), do: v
  defp to_integer(v) when is_binary(v), do: String.to_integer(v)
end
