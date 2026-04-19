defmodule Guarda.APIKeys do
  @moduledoc """
  An ETS-backed cache for validating API keys at zero overhead.
  """
  use GenServer
  require Logger

  @table_name :guarda_api_keys

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    # Create a public ETS table for blazing fast concurrent reads across requests
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # In a full implementation, this might hydrate from SQLite or Ecto on startup.
    Logger.info("ETS API Keys cache initialized for zero-latency queries.")
    {:ok, %{}}
  end

  @doc "Registers an API key directly into ETS memory."
  def register_key(key, user_claims) do
    :ets.insert(@table_name, {key, user_claims})
    :ok
  end

  @doc "Revokes an API key."
  def revoke_key(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc "Validates an API key. Returns {:ok, user_claims} or {:error, :unauthorized}"
  def validate(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, claims}] -> {:ok, claims}
      [] -> {:error, :unauthorized}
    end
  end
end
