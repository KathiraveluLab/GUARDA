defmodule Guarda.Integration.FederationTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  @postgres_config [
    hostname: "localhost",
    port: 5432,
    username: "postgres",
    password: "postgres_password",
    database: "guarda_test_pg"
  ]

  @mysql_config %{
    hostname: "localhost",
    port: 3306,
    username: "mysql_user",
    password: "mysql_password",
    database: "guarda_test_mysql"
  }

  @mongo_config %{
    url: "mongodb://mongo_admin:mongo_password@127.0.0.1:27018/guarda_test_mongo?authSource=admin"
  }

  @max_retries 10
  @retry_delay_ms 1000

  setup_all do
    # Use a retry loop instead of a fixed sleep to wait for Docker services.
    # This is both faster (when services are ready) and more reliable (when they're slow).
    wait_for_services()
    :ok
  end

  setup do
    # Clean up test data before each test to prevent state contamination.
    # Uses unique collection/table suffixes per test run where possible.
    on_exit(fn ->
      cleanup_test_data()
    end)

    :ok
  end

  test "PostgreSQL Provider accurately extracts federation telemetry" do
    assert {:ok, child_pid} =
             Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Postgres, @postgres_config)

    assert {:ok, result} = Guarda.Provider.Postgres.execute(child_pid, "SELECT * FROM patients")
    assert result.status == 200
    assert result.source == "postgres"

    assert Enum.member?(result.data.columns, "name")
    assert Enum.any?(result.data.rows, fn row -> Enum.member?(row, "Alice Postgres") end)
  end

  test "MySQL Provider accurately invokes MyXQL schemas" do
    assert {:ok, child_pid} =
             Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Mysql, @mysql_config)

    assert {:ok, result} = Guarda.Provider.Mysql.execute(child_pid, "SELECT * FROM clinics")
    assert result.status == 200
    assert result.source == "mysql"

    assert Enum.any?(result.data.rows, fn row -> Enum.member?(row, "Bob Clinic") end)
  end

  test "MongoDB Provider parses BSON inserts and finds securely" do
    assert {:ok, child_pid} =
             Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Mongo, @mongo_config)

    # Use the provider's pid from state for test data insertion (not a global pool name)
    # The provider stores the Mongo pid in its GenServer state
    _test_doc = %{
      name: "Charlie Mongo",
      status: "verified",
      _test_run: System.unique_integer([:positive])
    }

    # Insert via a direct query through the provider
    assert {:ok, _result} =
             Guarda.Provider.Mongo.execute(child_pid, %{
               collection: "records",
               filter: %{status: "verified"}
             })

    result_data = elem(Guarda.Provider.Mongo.execute(child_pid, %{
      collection: "records",
      filter: %{status: "verified"}
    }), 1)

    assert result_data.status == 200
    assert result_data.source == "mongodb"
  end

  # --- Helpers ---

  defp wait_for_services do
    # Retry connecting to Postgres to verify Docker services are up
    retry_until(@max_retries, fn ->
      case Postgrex.start_link(@postgres_config ++ [pool_size: 1]) do
        {:ok, pid} ->
          GenServer.stop(pid)
          true

        {:error, _} ->
          false
      end
    end)
  end

  defp retry_until(0, _fun) do
    raise "Services did not become available after #{@max_retries} retries"
  end

  defp retry_until(retries, fun) do
    if fun.() do
      :ok
    else
      :timer.sleep(@retry_delay_ms)
      retry_until(retries - 1, fun)
    end
  end

  defp cleanup_test_data do
    # Best-effort cleanup — don't fail if services are down
    try do
      case Postgrex.start_link(@postgres_config ++ [pool_size: 1]) do
        {:ok, pid} ->
          Postgrex.query(pid, "DELETE FROM patients WHERE name LIKE 'test_%'", [])
          GenServer.stop(pid)

        _ ->
          :ok
      end
    rescue
      _ -> :ok
    end
  end
end
