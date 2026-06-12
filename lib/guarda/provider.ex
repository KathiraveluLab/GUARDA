defmodule Guarda.Provider do
  @moduledoc """
  The core behaviour for all data source providers in the GUARDA federation gateway.

  Every specific data source (e.g., PostgreSQL, MongoDB, HTTP) must implement
  this behaviour. By wrapping the connection details inside this contract, the
  gateway can dynamically spawn and execute queries across diverse endpoints
  using isolated, fault-tolerant GenServer processes.

  ## Usage

      defmodule MyProvider do
        use Guarda.Provider

        @impl Guarda.Provider
        def init_provider(config), do: {:ok, config}

        @impl Guarda.Provider
        def execute_query(query, state), do: {:ok, %{data: query}}

        @impl Guarda.Provider
        def terminate_provider(_state), do: :ok
      end
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

  @doc """
  When `use Guarda.Provider` is invoked, it injects the behaviour declaration
  and compile-time checks into the implementing module.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Guarda.Provider

      # Compile-time check: ensure all required callbacks are implemented.
      # This will produce a warning at compile time if any callback is missing.
      @after_compile {Guarda.Provider, :validate_provider}
    end
  end

  @doc """
  Compile-time validation that ensures all required callbacks are implemented.
  Called automatically via @after_compile when using `use Guarda.Provider`.
  """
  def validate_provider(module, _bytecode) do
    required_callbacks = [:init_provider, :execute_query, :terminate_provider]

    exports = module.__info__(:functions)

    missing =
      Enum.filter(required_callbacks, fn callback ->
        not Keyword.has_key?(exports, callback)
      end)

    if missing != [] do
      IO.warn(
        "Module #{inspect(module)} is missing Guarda.Provider callbacks: #{inspect(missing)}",
        []
      )
    end
  end

  @doc """
  Runtime check to verify a module properly implements the Provider behaviour.
  Returns `:ok` if valid, `{:error, missing_callbacks}` otherwise.
  """
  def valid_provider?(module) do
    required = [init_provider: 1, execute_query: 2, terminate_provider: 1]

    exports = module.__info__(:functions)

    missing =
      Enum.reject(required, fn {name, arity} ->
        {name, arity} in exports
      end)

    if missing == [] do
      :ok
    else
      {:error, missing}
    end
  end
end
