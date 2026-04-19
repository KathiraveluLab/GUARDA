defmodule Guarda.Integration.FederationTest do
  use ExUnit.Case, async: false

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

  setup_all do
    # Allow Docker services to fully initialize before dialling.
    :timer.sleep(5000)
    :ok
  end

  test "PostgreSQL Provider accurately extracts federation telemetry" do
    assert {:ok, child_pid} = Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Postgres, @postgres_config)

    assert {:ok, result} = Guarda.Provider.Postgres.execute(child_pid, "SELECT * FROM patients")
    assert result.status == 200
    assert result.source == "postgres"

    assert Enum.member?(result.data.columns, "name")
    assert Enum.any?(result.data.rows, fn row -> Enum.member?(row, "Alice Postgres") end)
  end

  test "MySQL Provider accurately invokes MyXQL schemas" do
    assert {:ok, child_pid} = Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Mysql, @mysql_config)

    assert {:ok, result} = Guarda.Provider.Mysql.execute(child_pid, "SELECT * FROM clinics")
    assert result.status == 200
    assert result.source == "mysql"

    assert Enum.any?(result.data.rows, fn row -> Enum.member?(row, "Bob Clinic") end)
  end

  test "MongoDB Provider parses BSON inserts and finds securely" do
    assert {:ok, child_pid} = Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Mongo, @mongo_config)

    # Insert a test document via the shared pool started by the provider.
    Mongo.insert_one(:mongo_guarda_pool, "records", %{name: "Charlie Mongo", status: "verified"})

    assert {:ok, result} = Guarda.Provider.Mongo.execute(child_pid, %{collection: "records", filter: %{status: "verified"}})
    assert result.status == 200
    assert result.source == "mongodb"

    docs = result.data.documents
    assert length(docs) > 0
    assert Enum.any?(docs, fn doc -> doc["name"] == "Charlie Mongo" end)
  end
end

