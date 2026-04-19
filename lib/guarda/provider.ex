defmodule Guarda.Provider do
  @moduledoc """
  The core behaviour for all data source providers in the GUARDA federation gateway.

  Every specific data source (e.g., PostgreSQL, MongoDB, HTTP) must implement
  this behaviour. By wrapping the connection details inside this contract, the
  gateway can dynamically spawn and execute queries across diverse endpoints
  using isolated, fault-tolerant GenServer processes.
  """

  @doc """
  Initializes the provider with the unique configuration payload (credentials, host, etc.).
  Returns `{:ok, state}` upon successful connection, or an error tuple.
  """
  @callback init_provider(config :: map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Executes a given query (e.g., SQL string, HTTP path, or Mongo JSON filter)
  against the active provider connection.
  Returns `{:ok, result}` with the parsed payload, or `{:error, reason}`.
  """
  @callback execute_query(query :: term(), state :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Gracefully terminates the provider's remote connection.
  """
  @callback terminate_provider(state :: term()) :: :ok
end
