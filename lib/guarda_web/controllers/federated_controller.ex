defmodule GuardaWeb.FederatedController do
  @moduledoc "API controller for cross-provider federated JOIN queries."
  use GuardaWeb, :controller

  @providers %{
    "postgres" => Guarda.Provider.Postgres,
    "mysql" => Guarda.Provider.Mysql,
    "mongo" => Guarda.Provider.Mongo,
    "mongodb" => Guarda.Provider.Mongo
  }

  @doc """
  POST /api/query/federated

  Expects JSON:
  ```json
  {
    "left": {"provider": "postgres", "config": {...}, "query": "SELECT ...", "alias": "users"},
    "right": {"provider": "mysql", "config": {...}, "query": "SELECT ...", "alias": "orders"},
    "join_on": {"left_key": "id", "right_key": "user_id"},
    "join_type": "inner"
  }
  ```
  """
  def join(conn, params) do
    with {:ok, left} <- parse_side(params, "left"),
         {:ok, right} <- parse_side(params, "right"),
         {:ok, join_on} <- parse_join_on(params) do
      join_type = parse_join_type(Map.get(params, "join_type", "inner"))

      case Guarda.Federation.Join.execute(left, right, join_on, join_type) do
        {:ok, result} ->
          json(conn, %{status: "success", data: result})
        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{status: "error", error: reason})
      end
    else
      {:error, msg} -> conn |> put_status(:bad_request) |> json(%{error: msg})
    end
  end

  defp parse_side(params, side) do
    case Map.get(params, side) do
      %{"provider" => p, "config" => c, "query" => q} = s ->
        p = String.downcase(p)
        case Map.get(@providers, p) do
          nil -> {:error, "Unknown provider '#{p}' in #{side}"}
          module ->
            config = Guarda.ConfigHelper.safe_atomize_config(c)
            {:ok, %{module: module, config: config, query: q, alias: Map.get(s, "alias", side)}}
        end
      _ -> {:error, "Missing or invalid '#{side}' field"}
    end
  end

  defp parse_join_on(%{"join_on" => %{"left_key" => lk, "right_key" => rk}}) do
    {:ok, %{left_key: lk, right_key: rk}}
  end
  defp parse_join_on(_), do: {:error, "Missing 'join_on' with 'left_key' and 'right_key'"}

  defp parse_join_type("left"), do: :left
  defp parse_join_type("right"), do: :right
  defp parse_join_type(_), do: :inner
end
