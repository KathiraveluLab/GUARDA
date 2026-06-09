defmodule Guarda.APIKeys do
  @moduledoc """
  An ETS-backed cache for validating API keys at zero overhead.

  The ETS table is `:protected` — only this GenServer process can write to it.
  All other processes get read-only access. Key registration and revocation
  must go through GenServer.call/2 to prevent unauthorized writes.

  Supports multi-tenancy via optional `org_id` scoping and PubSub-based
  key sync across distributed nodes.
  """
  use GenServer
  require Logger

  @table_name :guarda_api_keys
  @sync_topic "api_keys:sync"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Protected ETS: only the owner (this GenServer) can write; everyone else reads
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])

    # Subscribe to PubSub for multi-node key sync
    Phoenix.PubSub.subscribe(Guarda.PubSub, @sync_topic)

    Logger.info("ETS API Keys cache initialized (protected mode, PubSub sync enabled).")
    {:ok, %{}}
  end

  @doc "Registers an API key with optional org_id for multi-tenancy."
  def register_key(key, user_claims, opts \\ []) do
    org_id = Keyword.get(opts, :org_id)
    GenServer.call(__MODULE__, {:register_key, key, user_claims, org_id})
  end

  @doc "Revokes an API key."
  def revoke_key(key) do
    GenServer.call(__MODULE__, {:revoke_key, key})
  end

  @doc "Lists all registered API keys with metadata."
  def list_keys do
    :ets.tab2list(@table_name)
    |> Enum.map(fn
      {key, %{claims: claims, org_id: org_id, label: label, created_at: created_at}} ->
        %{key: key, claims: claims, org_id: org_id, label: label, created_at: created_at}

      {key, %{} = meta} ->
        %{key: key, claims: meta[:claims] || meta, org_id: meta[:org_id], label: meta[:label], created_at: meta[:created_at]}

      {key, claims} ->
        %{key: key, claims: claims, org_id: nil, label: nil, created_at: nil}
    end)
  end

  @doc "Lists keys filtered by org_id for multi-tenancy."
  def list_keys_for_org(org_id) do
    list_keys()
    |> Enum.filter(fn entry -> entry.org_id == org_id end)
  end

  @doc "Validates an API key. Returns {:ok, user_claims} or {:error, :unauthorized}"
  def validate(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, %{claims: claims}}] -> {:ok, claims}
      [{^key, claims}] -> {:ok, claims}
      [] -> {:error, :unauthorized}
    end
  end

  @doc "Generates a cryptographically secure API key string."
  def generate_key do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  # --- GenServer Callbacks ---

  @impl true
  def handle_call({:register_key, key, user_claims, org_id}, _from, state) do
    entry = %{
      claims: user_claims,
      org_id: org_id,
      label: Map.get(user_claims, "label", nil),
      created_at: DateTime.utc_now()
    }

    :ets.insert(@table_name, {key, entry})
    Logger.info("API key registered for user: #{inspect(Map.get(user_claims, "user_id", "unknown"))}")

    # Broadcast to other nodes for sync
    Phoenix.PubSub.broadcast(Guarda.PubSub, @sync_topic, {:key_registered, key, entry, node()})
    # Broadcast to dashboard for real-time updates
    GuardaWeb.DashboardLive.broadcast_refresh()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:revoke_key, key}, _from, state) do
    :ets.delete(@table_name, key)
    Logger.info("API key revoked.")

    # Broadcast to other nodes for sync
    Phoenix.PubSub.broadcast(Guarda.PubSub, @sync_topic, {:key_revoked, key, node()})
    GuardaWeb.DashboardLive.broadcast_refresh()
    {:reply, :ok, state}
  end

  # --- PubSub Sync Handlers ---

  @impl true
  def handle_info({:key_registered, key, entry, origin_node}, state) do
    # Only apply if the message came from a different node
    if origin_node != node() do
      :ets.insert(@table_name, {key, entry})
      Logger.debug("Synced API key registration from #{origin_node}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:key_revoked, key, origin_node}, state) do
    if origin_node != node() do
      :ets.delete(@table_name, key)
      Logger.debug("Synced API key revocation from #{origin_node}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
