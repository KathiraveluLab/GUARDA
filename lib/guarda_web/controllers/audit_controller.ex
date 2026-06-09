defmodule GuardaWeb.AuditController do
  @moduledoc """
  API controller for querying the audit log.
  """
  use GuardaWeb, :controller

  @doc """
  GET /api/audit

  Query parameters:
    * `count` - Number of entries to return (default: 50, max: 500)
    * `user` - Filter by user identifier
    * `provider` - Filter by provider type
    * `status` - Filter by status ("ok" or "error")
  """
  def index(conn, params) do
    count = params |> Map.get("count", "50") |> String.to_integer() |> min(500)

    filters =
      params
      |> Map.take(["user", "provider", "status"])
      |> Enum.reduce(%{}, fn
        {"user", v}, acc -> Map.put(acc, :user, v)
        {"provider", v}, acc -> Map.put(acc, :provider, v)
        {"status", "ok"}, acc -> Map.put(acc, :status, :ok)
        {"status", "error"}, acc -> Map.put(acc, :status, :error)
        _, acc -> acc
      end)

    entries =
      if map_size(filters) > 0 do
        Guarda.AuditLog.search(filters)
      else
        Guarda.AuditLog.recent(count)
      end

    json(conn, %{
      status: "success",
      data: %{
        entries: Enum.map(entries, &serialize_entry/1),
        count: length(entries)
      }
    })
  end

  @doc "GET /api/audit/stats"
  def stats(conn, _params) do
    stats = Guarda.AuditLog.stats()
    json(conn, %{status: "success", data: stats})
  end

  defp serialize_entry(entry) do
    %{
      id: entry.id,
      user: entry.user,
      provider: entry.provider,
      query: entry.query,
      duration_ms: entry.duration_ms,
      status: to_string(entry.status),
      timestamp: DateTime.to_iso8601(entry.timestamp)
    }
  end
end
