defmodule Guarda.ConfigHelper do
  @moduledoc """
  Shared helper for safely converting user-supplied config maps
  into provider-compatible keyword lists or atom-keyed maps.

  Uses a whitelist of known keys to prevent atom table exhaustion
  from arbitrary user input.
  """

  @allowed_keys ~w(
    hostname host port username password database
    url pool_size ssl socket_dir timeout connect_timeout
    queue_target queue_interval name socket
    base_url headers method auth_source
  )

  @doc """
  Converts a string-keyed map from JSON into an atom-keyed map,
  only allowing known configuration keys.

  Unknown keys are silently dropped to prevent atom table exhaustion.
  """
  def safe_atomize_config(config) when is_map(config) do
    allowed_atoms = Map.new(@allowed_keys, fn k -> {k, String.to_existing_atom(k)} end)

    config
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_binary(k) ->
        case Map.get(allowed_atoms, k) do
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
