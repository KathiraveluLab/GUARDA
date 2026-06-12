defmodule Guarda.Provider.PostgresTest do
  use ExUnit.Case, async: true

  alias Guarda.Provider.Postgres

  describe "normalize_config/1" do
    test "passes through keyword lists unchanged" do
      config = [hostname: "localhost", database: "test"]
      assert Postgres.normalize_config(config) == config
    end

    test "converts atom-keyed maps to keyword lists" do
      config = %{hostname: "localhost", database: "test"}
      result = Postgres.normalize_config(config)

      assert is_list(result)
      assert Keyword.get(result, :hostname) == "localhost"
      assert Keyword.get(result, :database) == "test"
    end

    test "converts string-keyed maps with known keys to keyword lists" do
      config = %{"hostname" => "localhost", "database" => "test", "port" => 5432}
      result = Postgres.normalize_config(config)

      assert is_list(result)
      assert Keyword.get(result, :hostname) == "localhost"
      assert Keyword.get(result, :database) == "test"
      assert Keyword.get(result, :port) == 5432
    end

    test "skips unknown string keys to prevent atom exhaustion" do
      config = %{"hostname" => "localhost", "unknown_evil_key_12345" => "value"}
      result = Postgres.normalize_config(config)

      assert is_list(result)
      assert Keyword.get(result, :hostname) == "localhost"
      # Unknown key should be skipped
      assert length(result) == 1
    end
  end
end
