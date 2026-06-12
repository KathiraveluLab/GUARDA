defmodule GuardaWeb.NLQueryController do
  @moduledoc "API controller for natural language to SQL query translation."
  use GuardaWeb, :controller

  @allowed_providers %{"postgres" => Guarda.Provider.Postgres, "mysql" => Guarda.Provider.Mysql}

  @doc "POST /api/query/natural — translate natural language to SQL and execute"
  def translate(conn, params) do
    with {:ok, question} <- get_field(params, "question"),
         {:ok, provider_type} <- get_field(params, "provider"),
         {:ok, config} <- validate_config(params),
         {:ok, module} <- resolve_module(provider_type) do
      schema = Map.get(params, "schema", [])
      opts = if key = Map.get(params, "api_key"), do: [api_key: key], else: []

      case Map.get(params, "execute", true) do
        true ->
          case Guarda.NLQuery.translate(question, schema, provider_type, opts) do
            {:ok, sql} ->
              # Execute the generated SQL
              case execute_sql(module, config, sql) do
                {:ok, data} ->
                  json(conn, %{status: "success", generated_sql: sql, data: data})
                {:error, reason} ->
                  conn |> put_status(:unprocessable_entity) |> json(%{status: "error", generated_sql: sql, error: inspect(reason)})
              end
            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
          end

        false ->
          case Guarda.NLQuery.translate(question, schema, provider_type, opts) do
            {:ok, sql} -> json(conn, %{status: "success", generated_sql: sql})
            {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: reason})
          end
      end
    else
      {:error, msg} -> conn |> put_status(:bad_request) |> json(%{error: msg})
    end
  end

  defp get_field(params, field) do
    case Map.get(params, field) do
      nil -> {:error, "Missing '#{field}'"}
      val -> {:ok, val}
    end
  end

  defp validate_config(%{"config" => c}) when is_map(c) do
    {:ok, Guarda.ConfigHelper.safe_atomize_config(c)}
  end
  defp validate_config(_), do: {:error, "Missing 'config'"}

  defp resolve_module(type) do
    type = String.downcase(type)
    case Map.get(@allowed_providers, type) do
      nil -> {:error, "NL-to-SQL only supports postgres and mysql"}
      m -> {:ok, m}
    end
  end

  defp execute_sql(module, config, sql) do
    case Guarda.ProviderSupervisor.start_provider(module, config) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, {:execute_query, sql}, 30_000)
        after
          Guarda.ProviderSupervisor.stop_provider(pid)
        end
      error -> error
    end
  end
end
