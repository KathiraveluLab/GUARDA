defmodule Guarda.APIKeysTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn ->
      Guarda.APIKeys.list_keys()
      |> Enum.each(fn entry ->
        if String.starts_with?(entry.key, "test_") do
          Guarda.APIKeys.revoke_key(entry.key)
        end
      end)
    end)

    :ok
  end

  test "register_key/2 and validate/1 work correctly" do
    key = "test_key_#{System.unique_integer([:positive])}"
    claims = %{"user_id" => "test_user", "scope" => "read"}

    assert :ok = Guarda.APIKeys.register_key(key, claims)
    assert {:ok, ^claims} = Guarda.APIKeys.validate(key)
  end

  test "validate/1 returns error for unknown keys" do
    assert {:error, :unauthorized} = Guarda.APIKeys.validate("nonexistent_key")
  end

  test "revoke_key/1 removes a registered key" do
    key = "test_revoke_#{System.unique_integer([:positive])}"
    claims = %{"user_id" => "to_revoke"}

    :ok = Guarda.APIKeys.register_key(key, claims)
    assert {:ok, _} = Guarda.APIKeys.validate(key)

    :ok = Guarda.APIKeys.revoke_key(key)
    assert {:error, :unauthorized} = Guarda.APIKeys.validate(key)
  end

  test "list_keys/0 returns all registered keys as maps" do
    key1 = "test_list_1_#{System.unique_integer([:positive])}"
    key2 = "test_list_2_#{System.unique_integer([:positive])}"

    Guarda.APIKeys.register_key(key1, %{"user_id" => "user1"})
    Guarda.APIKeys.register_key(key2, %{"user_id" => "user2"})

    keys = Guarda.APIKeys.list_keys()
    registered_keys = Enum.map(keys, & &1.key)

    assert key1 in registered_keys
    assert key2 in registered_keys
  end

  test "ETS table is protected (external writes should fail)" do
    assert_raise ArgumentError, fn ->
      :ets.insert(:guarda_api_keys, {"hacked_key", %{"admin" => true}})
    end
  end
end
