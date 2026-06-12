defmodule Guarda.HealthMonitor do
  @moduledoc """
  Periodic health monitor for active data providers.

  Tracks connection health, latency, and error rates for each
  provider actor managed by the ProviderSupervisor. Broadcasts
  health updates to the dashboard via PubSub.
  """
  use GenServer
  require Logger

  @health_topic "provider:health"
  @check_interval 30_000  # 30 seconds

  # --- Client API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Returns the current health status for all monitored providers."
  def get_health do
    GenServer.call(__MODULE__, :get_health)
  end

  @doc "Records a query result for health tracking."
  def record_query(provider_type, duration_ms, status) do
    GenServer.cast(__MODULE__, {:record_query, provider_type, duration_ms, status})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_) do
    :timer.send_interval(@check_interval, self(), :health_check)
    {:ok, %{providers: %{}}}
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_cast({:record_query, provider_type, duration_ms, status}, state) do
    provider_health = Map.get(state.providers, provider_type, default_health())

    updated =
      provider_health
      |> Map.update!(:total_queries, &(&1 + 1))
      |> Map.update!(:latency_samples, fn samples ->
        [duration_ms | Enum.take(samples, 99)]  # Keep last 100 samples
      end)
      |> Map.put(:last_query_at, DateTime.utc_now())
      |> then(fn h ->
        case status do
          :ok -> Map.update!(h, :success_count, &(&1 + 1))
          :error -> Map.update!(h, :error_count, &(&1 + 1))
        end
      end)
      |> compute_stats()

    new_state = put_in(state, [:providers, provider_type], updated)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Get active provider count from supervisor
    active =
      try do
        children = DynamicSupervisor.count_children(Guarda.ProviderSupervisor)
        children.active || 0
      rescue
        _ -> 0
      end

    # Broadcast health status to dashboard
    health_summary = %{
      active_providers: active,
      provider_health: state.providers,
      checked_at: DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(Guarda.PubSub, @health_topic, {:health_update, health_summary})

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp default_health do
    %{
      total_queries: 0,
      success_count: 0,
      error_count: 0,
      latency_samples: [],
      avg_latency_ms: 0,
      p95_latency_ms: 0,
      error_rate: 0.0,
      last_query_at: nil,
      status: :healthy
    }
  end

  defp compute_stats(health) do
    total = health.total_queries

    error_rate =
      if total > 0 do
        health.error_count / total
      else
        0.0
      end

    avg_latency =
      case health.latency_samples do
        [] -> 0
        samples -> Enum.sum(samples) |> div(length(samples))
      end

    p95_latency =
      case health.latency_samples do
        [] ->
          0

        samples ->
          sorted = Enum.sort(samples)
          idx = round(length(sorted) * 0.95) - 1
          Enum.at(sorted, max(idx, 0), 0)
      end

    status =
      cond do
        error_rate > 0.5 -> :unhealthy
        error_rate > 0.1 -> :degraded
        true -> :healthy
      end

    health
    |> Map.put(:avg_latency_ms, avg_latency)
    |> Map.put(:p95_latency_ms, p95_latency)
    |> Map.put(:error_rate, Float.round(error_rate, 3))
    |> Map.put(:status, status)
  end
end
