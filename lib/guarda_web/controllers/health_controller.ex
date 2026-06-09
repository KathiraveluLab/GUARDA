defmodule GuardaWeb.HealthController do
  @moduledoc """
  API controller for system and per-provider health checks.
  """
  use GuardaWeb, :controller

  @doc """
  GET /api/health

  Returns overall system health including:
  - Active provider count
  - Per-provider health metrics (latency, error rate, status)
  - API key count
  - Cache stats
  """
  def index(conn, _params) do
    provider_health = Guarda.HealthMonitor.get_health()
    cache_stats = Guarda.QueryCache.stats()

    active_providers =
      try do
        children = DynamicSupervisor.count_children(Guarda.ProviderSupervisor)
        children.active || 0
      rescue
        _ -> 0
      end

    api_key_count =
      try do
        case :ets.info(:guarda_api_keys, :size) do
          :undefined -> 0
          size -> size
        end
      rescue
        _ -> 0
      end

    health = %{
      status: system_status(provider_health),
      active_providers: active_providers,
      api_key_count: api_key_count,
      cache: cache_stats,
      providers: format_provider_health(provider_health),
      checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    status_code = if health.status == "healthy", do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health)
  end

  defp system_status(provider_health) do
    statuses = Map.values(provider_health) |> Enum.map(& &1.status)

    cond do
      Enum.any?(statuses, &(&1 == :unhealthy)) -> "unhealthy"
      Enum.any?(statuses, &(&1 == :degraded)) -> "degraded"
      true -> "healthy"
    end
  end

  defp format_provider_health(provider_health) do
    Map.new(provider_health, fn {provider, health} ->
      {provider, %{
        status: to_string(health.status),
        total_queries: health.total_queries,
        success_count: health.success_count,
        error_count: health.error_count,
        avg_latency_ms: health.avg_latency_ms,
        p95_latency_ms: health.p95_latency_ms,
        error_rate: health.error_rate,
        last_query_at: if(health.last_query_at, do: DateTime.to_iso8601(health.last_query_at))
      }}
    end)
  end
end
