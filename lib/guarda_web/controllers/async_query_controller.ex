defmodule GuardaWeb.AsyncQueryController do
  @moduledoc "API controller for async query submission and status polling."
  use GuardaWeb, :controller

  @allowed_providers %{
    "postgres" => Guarda.Provider.Postgres,
    "mysql" => Guarda.Provider.Mysql,
    "mongo" => Guarda.Provider.Mongo,
    "mongodb" => Guarda.Provider.Mongo,
    "http" => Guarda.Provider.Http
  }

  @doc "POST /api/query/async — submit a query for async execution with webhook callback"
  def submit(conn, params) do
    with {:ok, provider_type} <- validate_field(params, "provider"),
         {:ok, config} <- validate_config(params),
         {:ok, query} <- validate_field(params, "query"),
         {:ok, module} <- resolve_module(provider_type) do
      callback_url = Map.get(params, "callback_url")
      query_params = Map.get(params, "params", [])
      user = extract_user(conn)

      case Guarda.AsyncQuery.submit(module, provider_type, config, query, query_params, callback_url, user) do
        {:ok, query_id} ->
          conn |> put_status(:accepted) |> json(%{
            status: "accepted",
            query_id: query_id,
            poll_url: "/api/query/#{query_id}/status"
          })
      end
    else
      {:error, msg} -> conn |> put_status(:bad_request) |> json(%{error: msg})
    end
  end

  @doc "GET /api/query/:id/status — poll for async query status"
  def status(conn, %{"id" => query_id}) do
    case Guarda.AsyncQuery.get_status(query_id) do
      {:ok, entry} ->
        json(conn, %{
          query_id: entry.id,
          status: to_string(entry.status),
          provider: entry.provider,
          submitted_at: DateTime.to_iso8601(entry.submitted_at),
          completed_at: if(entry.completed_at, do: DateTime.to_iso8601(entry.completed_at)),
          result: if(entry.status == :completed, do: entry.result),
          error: entry.error
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Query not found"})
    end
  end

  defp validate_field(params, field) do
    case Map.get(params, field) do
      nil -> {:error, "Missing '#{field}'"}
      val -> {:ok, val}
    end
  end

  defp validate_config(%{"config" => c}) when is_map(c) do
    {:ok, Guarda.ConfigHelper.safe_atomize_config(c)}
  end
  defp validate_config(_), do: {:error, "Missing 'config'"}

  defp resolve_module(type) do
    type = String.downcase(type)
    case Map.get(@allowed_providers, type) do
      nil -> {:error, "Unknown provider"}
      m -> {:ok, m}
    end
  end

  defp extract_user(conn) do
    case Map.get(conn.assigns, :current_user) do
      nil -> "anonymous"
      u when is_binary(u) -> u
      u when is_map(u) -> Map.get(u, "user_id", "unknown")
      _ -> "unknown"
    end
  end
end
