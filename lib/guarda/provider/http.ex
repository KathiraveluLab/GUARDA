defmodule Guarda.Provider.Http do
  use GenServer
  @behaviour Guarda.Provider

  require Logger

  # Client API

  def start_link(config) do
    # We could name the process or register it via a Registry for dynamic supervision
    GenServer.start_link(__MODULE__, config)
  end

  def execute(pid, endpoint_path) do
    GenServer.call(pid, {:execute_query, endpoint_path})
  end

  # Server Callbacks

  @impl true
  def init(config) do
    case init_provider(config) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:execute_query, endpoint_path}, _from, state) do
    case execute_query(endpoint_path, state) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    terminate_provider(state)
  end

  # Provider Behaviour Implementation

  @impl Guarda.Provider
  def init_provider(config) do
    # For HTTP, the config contains base_url, authentication headers, etc.
    Logger.info("Initializing HTTP Provider actor with config: #{inspect(config)}")
    {:ok, config}
  end

  @impl Guarda.Provider
  def execute_query(endpoint_path, state) do
    base_url = Map.get(state, :base_url, "http://localhost")
    target_url = "#{base_url}#{endpoint_path}"
    Logger.info("Executing federated HTTP GET on: #{target_url}")

    headers = Map.get(state, :headers, [])

    case Req.get(target_url, headers: headers) do
      {:ok, response} ->
        {:ok, %{status: response.status, source: "http", data: response.body}}

      {:error, exception} ->
        Logger.error("HTTP request failed: #{inspect(exception)}")
        {:error, exception}
    end
  end

  @impl Guarda.Provider
  def terminate_provider(_state) do
    Logger.info("Terminating HTTP Provider actor")
    :ok
  end
end
