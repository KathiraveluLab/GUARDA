defmodule Guarda.ConfigHelper do
  @moduledoc """
  Shared helper for safely converting user-supplied config maps
  into provider-compatible keyword lists or atom-keyed maps.

  Uses a whitelist of known keys to prevent atom table exhaustion
  from arbitrary user input.
  """

  # Pre-built mapping from string keys to atom keys.
  # Using atom literals here guarantees they exist at compile time.
  @allowed_atoms %{
    "hostname" => :hostname,
    "host" => :host,
    "port" => :port,
    "username" => :username,
    "password" => :password,
    "database" => :database,
    "url" => :url,
    "pool_size" => :pool_size,
    "ssl" => :ssl,
    "socket_dir" => :socket_dir,
    "timeout" => :timeout,
    "connect_timeout" => :connect_timeout,
    "name" => :name,
    "socket" => :socket,
    "base_url" => :base_url,
    "headers" => :headers,
    "method" => :method,
    "auth_source" => :auth_source,
    "queue_target" => :queue_target,
    "queue_interval" => :queue_interval
  }

  @doc """
  Converts a string-keyed map from JSON into an atom-keyed map,
  only allowing known configuration keys.

  Unknown keys are silently dropped to prevent atom table exhaustion.
  """
  def safe_atomize_config(config) when is_map(config) do
    config
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_binary(k) ->
        case Map.get(@allowed_atoms, k) do
          nil -> acc
          atom_key -> Map.put(acc, atom_key, v)
        end

      {k, v}, acc when is_atom(k) ->
        Map.put(acc, k, v)

      _, acc ->
        acc
    end)
  end

  def safe_atomize_config(config) when is_list(config), do: config
end
