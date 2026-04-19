defmodule GuardaWeb.DashboardLive do
  use GuardaWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 2 seconds
      :timer.send_interval(2000, self(), :tick)
    end

    {:ok, assign_stats(socket)}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign_stats(socket)}
  end

  defp assign_stats(socket) do
    # Get active Provider connections from the DynamicSupervisor
    active_providers = DynamicSupervisor.count_children(Guarda.ProviderSupervisor)

    # Get cached API key count from ETS
    api_key_count =
      case :ets.info(:guarda_api_keys, :size) do
        :undefined -> 0
        size -> size
      end

    socket
    |> assign(:providers_active, active_providers.active || 0)
    |> assign(:api_key_count, api_key_count)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <GuardaWeb.Layouts.app flash={@flash} current_scope={assigns[:current_scope] || :dashboard}>
      <div class="max-w-4xl mx-auto p-4">
        <div class="mb-8 p-6 bg-gradient-to-r from-indigo-700 to-purple-800 rounded-xl shadow-2xl text-white">
          <h1 class="text-3xl font-extrabold tracking-tight mb-2 flex items-center gap-3">
            <.icon name="hero-server-stack" class="w-8 h-8" /> GUARDA Command Center
          </h1>
          <p class="text-indigo-100 font-medium">Federated Gateway & Analytics Hub</p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="bg-white rounded-xl shadow-lg border border-slate-100 p-6 transition-all hover:shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-bold text-slate-800">Active Data Providers</h2>
              <.icon name="hero-bolt" class="w-6 h-6 text-amber-500" />
            </div>
            <div class="flex items-baseline gap-2">
              <span class="text-5xl font-black text-indigo-600">{@providers_active}</span>
              <span class="text-sm text-slate-500 font-medium">Live Connection Actors</span>
            </div>
            <p class="mt-4 text-sm text-slate-600">
              Federated queries safely managed by the pristine OTP DynamicSupervisor.
            </p>
          </div>

          <div class="bg-white rounded-xl shadow-lg border border-slate-100 p-6 transition-all hover:shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-bold text-slate-800">API Security Perimeter</h2>
              <.icon name="hero-shield-check" class="w-6 h-6 text-emerald-500" />
            </div>
            <div class="flex items-baseline gap-2">
              <span class="text-5xl font-black text-emerald-600">{@api_key_count}</span>
              <span class="text-sm text-slate-500 font-medium">Cached Access Keys</span>
            </div>
            <p class="mt-4 text-sm text-slate-600">
              Keys validated in real-time micro-seconds via ETS memory tables.
            </p>
          </div>
        </div>
      </div>
    </GuardaWeb.Layouts.app>
    """
  end
end
