defmodule GuardaWeb.DashboardLive do
  use GuardaWeb, :live_view

  require Logger

  @refresh_topic "dashboard:refresh"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Guarda.PubSub, @refresh_topic)
      :timer.send_interval(30_000, self(), :tick)
    end

    socket =
      socket
      |> assign_stats()
      |> assign(:api_keys, load_api_keys())
      |> assign(:show_key_form, false)
      |> assign(:new_key_label, "")
      |> assign(:new_key_user_id, "")
      |> assign(:generated_key, nil)

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, socket |> assign_stats() |> assign(:api_keys, load_api_keys())}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply, socket |> assign_stats() |> assign(:api_keys, load_api_keys())}
  end

  # --- Event Handlers for API Key Management ---

  @impl true
  def handle_event("toggle_key_form", _params, socket) do
    {:noreply, assign(socket, :show_key_form, !socket.assigns.show_key_form)}
  end

  @impl true
  def handle_event("create_key", %{"label" => label, "user_id" => user_id}, socket) do
    key = Guarda.APIKeys.generate_key()
    claims = %{"user_id" => user_id, "label" => label, "scope" => "read"}

    case Guarda.APIKeys.register_key(key, claims) do
      :ok ->
        socket =
          socket
          |> assign(:api_keys, load_api_keys())
          |> assign(:generated_key, key)
          |> assign(:show_key_form, false)
          |> assign_stats()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke_key", %{"key" => key}, socket) do
    Guarda.APIKeys.revoke_key(key)

    socket =
      socket
      |> assign(:api_keys, load_api_keys())
      |> assign(:generated_key, nil)
      |> assign_stats()

    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_key", _params, socket) do
    {:noreply, assign(socket, :generated_key, nil)}
  end

  @doc """
  Broadcast a stats refresh to all connected dashboard clients.
  Call this from ProviderSupervisor/APIKeys when state actually changes.
  """
  def broadcast_refresh do
    Phoenix.PubSub.broadcast(Guarda.PubSub, @refresh_topic, :refresh_stats)
  end

  defp assign_stats(socket) do
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

    socket
    |> assign(:providers_active, active_providers)
    |> assign(:api_key_count, api_key_count)
  end

  defp load_api_keys do
    try do
      Guarda.APIKeys.list_keys()
    rescue
      _ -> []
    end
  end

  defp mask_key(key) when is_binary(key) and byte_size(key) > 8 do
    String.slice(key, 0, 8) <> "..." <> String.slice(key, -4, 4)
  end
  defp mask_key(key), do: key

  @impl true
  def render(assigns) do
    ~H"""
    <GuardaWeb.Layouts.app flash={@flash} current_scope={assigns[:current_scope] || :dashboard}>
      <div class="max-w-6xl mx-auto p-4">
        <div class="mb-8 p-6 bg-gradient-to-r from-indigo-700 to-purple-800 rounded-xl shadow-2xl text-white">
          <h1 class="text-3xl font-extrabold tracking-tight mb-2 flex items-center gap-3">
            <.icon name="hero-server-stack" class="w-8 h-8" /> GUARDA Command Center
          </h1>
          <p class="text-indigo-100 font-medium">Federated Gateway & Analytics Hub</p>
        </div>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <div class="bg-white rounded-xl shadow-lg border border-slate-100 p-6 transition-all hover:shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-bold text-slate-800">Active Data Providers</h2>
              <.icon name="hero-bolt" class="w-6 h-6 text-amber-500" />
            </div>
            <div class="flex items-baseline gap-2">
              <span class="text-5xl font-black text-indigo-600">{@providers_active}</span>
              <span class="text-sm text-slate-500 font-medium">Live Connection Actors</span>
            </div>
          </div>

          <div class="bg-white rounded-xl shadow-lg border border-slate-100 p-6 transition-all hover:shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-bold text-slate-800">API Security Perimeter</h2>
              <.icon name="hero-shield-check" class="w-6 h-6 text-emerald-500" />
            </div>
            <div class="flex items-baseline gap-2">
              <span class="text-5xl font-black text-emerald-600">{@api_key_count}</span>
              <span class="text-sm text-slate-500 font-medium">Registered API Keys</span>
            </div>
          </div>
        </div>

        <%!-- API Key Management Panel --%>
        <div class="bg-white rounded-xl shadow-lg border border-slate-100 p-6 mb-8">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-xl font-bold text-slate-800">API Key Management</h2>
            <button
              phx-click="toggle_key_form"
              class="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition-colors"
            >
              {if @show_key_form, do: "Cancel", else: "Create New Key"}
            </button>
          </div>

          <%!-- Generated Key Display --%>
          <%= if @generated_key do %>
            <div class="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg">
              <p class="text-sm font-medium text-green-800 mb-2">Key created. Copy it now — it will not be shown again.</p>
              <code class="block p-2 bg-white rounded border text-sm font-mono break-all">{@generated_key}</code>
              <button phx-click="dismiss_key" class="mt-2 text-sm text-green-700 underline">Dismiss</button>
            </div>
          <% end %>

          <%!-- Create Key Form --%>
          <%= if @show_key_form do %>
            <form phx-submit="create_key" class="mb-6 p-4 bg-slate-50 rounded-lg">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                <div>
                  <label class="block text-sm font-medium text-slate-700 mb-1">Label</label>
                  <input type="text" name="label" required placeholder="e.g. production-backend"
                    class="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500" />
                </div>
                <div>
                  <label class="block text-sm font-medium text-slate-700 mb-1">User ID</label>
                  <input type="text" name="user_id" required placeholder="e.g. service-account-1"
                    class="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500" />
                </div>
              </div>
              <button type="submit" class="px-4 py-2 bg-emerald-600 text-white rounded-lg text-sm font-medium hover:bg-emerald-700 transition-colors">
                Generate Key
              </button>
            </form>
          <% end %>

          <%!-- Key List --%>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-slate-200">
                  <th class="text-left py-3 px-2 font-semibold text-slate-600">Key</th>
                  <th class="text-left py-3 px-2 font-semibold text-slate-600">User</th>
                  <th class="text-left py-3 px-2 font-semibold text-slate-600">Label</th>
                  <th class="text-left py-3 px-2 font-semibold text-slate-600">Created</th>
                  <th class="text-right py-3 px-2 font-semibold text-slate-600">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @api_keys do %>
                  <tr class="border-b border-slate-100 hover:bg-slate-50">
                    <td class="py-3 px-2 font-mono text-xs">{mask_key(entry.key)}</td>
                    <td class="py-3 px-2">{get_in(entry, [:claims, "user_id"]) || "—"}</td>
                    <td class="py-3 px-2">{entry.label || "—"}</td>
                    <td class="py-3 px-2 text-slate-500">
                      {if entry.created_at, do: Calendar.strftime(entry.created_at, "%Y-%m-%d %H:%M"), else: "—"}
                    </td>
                    <td class="py-3 px-2 text-right">
                      <button
                        phx-click="revoke_key"
                        phx-value-key={entry.key}
                        data-confirm="Revoke this API key? This cannot be undone."
                        class="px-3 py-1 text-xs bg-red-50 text-red-700 rounded border border-red-200 hover:bg-red-100 transition-colors"
                      >
                        Revoke
                      </button>
                    </td>
                  </tr>
                <% end %>
                <%= if @api_keys == [] do %>
                  <tr>
                    <td colspan="5" class="py-8 text-center text-slate-400">No API keys registered.</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </GuardaWeb.Layouts.app>
    """
  end
end
