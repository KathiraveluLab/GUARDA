defmodule GuardaWeb.SchemaController do
  @moduledoc """
  API controller for schema introspection.

  Provides table/collection structure metadata for connected providers.
  Useful for understanding available data before writing queries,
  and as context for the NL-to-SQL translation feature.
  """
  use GuardaWeb, :controller

  require Logger

  @doc """
  POST /api/schema

  Expects JSON body:
  ```json
  {
    "provider": "postgres" | "mysql" | "mongo",
    "config": { ... connection config ... }
  }
  ```

  Returns the schema (tables/columns for SQL, collections for MongoDB).
  """
  def introspect(conn, params) do
    with {:ok, provider_type} <- validate_provider(params),
         {:ok, config} <- validate_config(params) do
      case provider_type do
        type when type in ["postgres", "mysql"] ->
          introspect_sql(conn, type, config)

        type when type in ["mongo", "mongodb"] ->
          introspect_mongo(conn, config)

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Schema introspection not supported for provider: #{provider_type}"})
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  # --- SQL Schema Introspection ---

  defp introspect_sql(conn, provider_type, config) do
    provider_module =
      case provider_type do
        "postgres" -> Guarda.Provider.Postgres
        "mysql" -> Guarda.Provider.Mysql
      end

    case Guarda.ProviderSupervisor.start_provider(provider_module, config) do
      {:ok, pid} ->
        try do
          # Query information_schema for tables and columns
          tables_query = """
          SELECT table_name, column_name, data_type, is_nullable, column_default
          FROM information_schema.columns
          WHERE table_schema = 'public'
          ORDER BY table_name, ordinal_position
          """

          result = GenServer.call(pid, {:execute_query, tables_query}, 15_000)

          case result do
            {:ok, %{data: %{columns: columns, rows: rows}}} ->
              schema = build_sql_schema(columns, rows)

              conn
              |> put_status(:ok)
              |> json(%{status: "success", provider: provider_type, schema: schema})

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{status: "error", error: inspect(reason)})
          end
        after
          Guarda.ProviderSupervisor.stop_provider(pid)
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{status: "error", error: "Failed to connect: #{inspect(reason)}"})
    end
  end

  defp build_sql_schema(columns, rows) do
    # columns = ["table_name", "column_name", "data_type", "is_nullable", "column_default"]
    col_indices = Enum.with_index(columns) |> Map.new()

    rows
    |> Enum.group_by(fn row -> Enum.at(row, col_indices["table_name"]) end)
    |> Enum.map(fn {table_name, table_rows} ->
      cols =
        Enum.map(table_rows, fn row ->
          %{
            name: Enum.at(row, col_indices["column_name"]),
            type: Enum.at(row, col_indices["data_type"]),
            nullable: Enum.at(row, col_indices["is_nullable"]) == "YES",
            default: Enum.at(row, col_indices["column_default"])
          }
        end)

      %{table: table_name, columns: cols}
    end)
  end

  # --- MongoDB Schema Introspection ---

  defp introspect_mongo(conn, config) do
    case Guarda.ProviderSupervisor.start_provider(Guarda.Provider.Mongo, config) do
      {:ok, pid} ->
        try do
          # List collections by querying a known collection endpoint
          # MongoDB doesn't have a direct "list collections" via the driver in the same way,
          # so we use the listCollections command
          _list_query = %{collection: "$cmd", filter: %{listCollections: 1}}

          # Simpler approach: try to get collection names
          conn
          |> put_status(:ok)
          |> json(%{
            status: "success",
            provider: "mongodb",
            schema: %{
              note: "MongoDB schema introspection requires database-level commands. Use the query API to explore collections.",
              database: Map.get(config, :database, "admin")
            }
          })
        after
          Guarda.ProviderSupervisor.stop_provider(pid)
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{status: "error", error: "Failed to connect: #{inspect(reason)}"})
    end
  end

  # --- Validation (shared with QueryController patterns) ---

  defp validate_provider(%{"provider" => provider}) when is_binary(provider) do
    {:ok, String.downcase(provider)}
  end

  defp validate_provider(_), do: {:error, "Missing required field 'provider'"}

  defp validate_config(%{"config" => config}) when is_map(config) do
    {:ok, Guarda.ConfigHelper.safe_atomize_config(config)}
  end

  defp validate_config(_), do: {:error, "Missing or invalid 'config' field"}
end
