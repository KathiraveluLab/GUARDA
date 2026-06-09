defmodule Guarda.Federation.Join do
  @moduledoc """
  Cross-provider federated JOIN engine.
  Executes sub-queries on individual providers in parallel,
  then performs the join in-memory on the GUARDA node.
  """
  require Logger

  @doc """
  Performs a federated JOIN across two providers.

  ## Parameters
    * `left` - %{module: Module, config: map, query: term, alias: string}
    * `right` - %{module: Module, config: map, query: term, alias: string}
    * `join_on` - %{left_key: string, right_key: string}
    * `join_type` - :inner | :left | :right (default: :inner)
  """
  def execute(left, right, join_on, join_type \\ :inner) do
    # Execute both queries in parallel
    left_task = Task.async(fn -> execute_side(left) end)
    right_task = Task.async(fn -> execute_side(right) end)

    left_result = Task.await(left_task, 30_000)
    right_result = Task.await(right_task, 30_000)

    case {left_result, right_result} do
      {{:ok, left_data}, {:ok, right_data}} ->
        joined = perform_join(left_data, right_data, join_on, join_type)
        {:ok, %{
          join_type: join_type,
          left_source: left[:alias] || "left",
          right_source: right[:alias] || "right",
          left_count: count_records(left_data),
          right_count: count_records(right_data),
          result_count: length(joined),
          columns: merge_columns(left_data, right_data, left[:alias], right[:alias]),
          rows: joined
        }}

      {{:error, reason}, _} ->
        {:error, "Left query failed: #{inspect(reason)}"}

      {_, {:error, reason}} ->
        {:error, "Right query failed: #{inspect(reason)}"}
    end
  end

  defp execute_side(%{module: module, config: config, query: query}) do
    case Guarda.ProviderSupervisor.start_provider(module, config) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, {:execute_query, query}, 30_000)
        after
          Guarda.ProviderSupervisor.stop_provider(pid)
        end
      error -> error
    end
  end

  defp perform_join(left, right, %{left_key: lk, right_key: rk}, join_type) do
    left_rows = to_row_maps(left)
    right_rows = to_row_maps(right)

    # Build index on right side for efficiency
    right_index = Enum.group_by(right_rows, &Map.get(&1, rk))

    case join_type do
      :inner ->
        Enum.flat_map(left_rows, fn lr ->
          key = Map.get(lr, lk)
          matches = Map.get(right_index, key, [])
          Enum.map(matches, fn rr -> Map.merge(prefix_keys(lr, "left"), prefix_keys(rr, "right")) end)
        end)

      :left ->
        Enum.flat_map(left_rows, fn lr ->
          key = Map.get(lr, lk)
          case Map.get(right_index, key, []) do
            [] -> [prefix_keys(lr, "left")]
            matches -> Enum.map(matches, fn rr -> Map.merge(prefix_keys(lr, "left"), prefix_keys(rr, "right")) end)
          end
        end)

      :right ->
        left_index = Enum.group_by(left_rows, &Map.get(&1, lk))
        Enum.flat_map(right_rows, fn rr ->
          key = Map.get(rr, rk)
          case Map.get(left_index, key, []) do
            [] -> [prefix_keys(rr, "right")]
            matches -> Enum.map(matches, fn lr -> Map.merge(prefix_keys(lr, "left"), prefix_keys(rr, "right")) end)
          end
        end)
    end
  end

  defp to_row_maps(%{data: %{columns: columns, rows: rows}}) do
    Enum.map(rows, fn row -> Enum.zip(columns, row) |> Map.new() end)
  end

  defp to_row_maps(%{data: %{documents: docs}}), do: docs
  defp to_row_maps(_), do: []

  defp count_records(%{data: %{rows: rows}}), do: length(rows)
  defp count_records(%{data: %{documents: docs}}), do: length(docs)
  defp count_records(_), do: 0

  defp prefix_keys(map, prefix) do
    Map.new(map, fn {k, v} -> {"#{prefix}.#{k}", v} end)
  end

  defp merge_columns(left, right, left_alias, right_alias) do
    la = left_alias || "left"
    ra = right_alias || "right"
    left_cols = get_source_columns(left) |> Enum.map(&"#{la}.#{&1}")
    right_cols = get_source_columns(right) |> Enum.map(&"#{ra}.#{&1}")
    left_cols ++ right_cols
  end

  defp get_source_columns(%{data: %{columns: cols}}), do: cols
  defp get_source_columns(%{data: %{documents: [first | _]}}) when is_map(first), do: Map.keys(first)
  defp get_source_columns(_), do: []
end
