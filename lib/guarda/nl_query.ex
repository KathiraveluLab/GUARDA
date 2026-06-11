defmodule Guarda.NLQuery do
  @moduledoc """
  Natural Language to SQL translation using OpenAI-compatible LLM API.
  Validates generated SQL through safe_query? before execution.
  """
  require Logger

  @default_model "gpt-3.5-turbo"
  @default_api_url "https://api.openai.com/v1/chat/completions"

  def translate(question, schema, provider_type, opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("OPENAI_API_KEY")
    model = Keyword.get(opts, :model, @default_model)
    api_url = Keyword.get(opts, :api_url, @default_api_url)

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENAI_API_KEY not configured"}
    else
      dialect = if provider_type == "mysql", do: "MySQL", else: "PostgreSQL"
      schema_text = format_schema(schema)

      system_prompt = "You are a SQL generator. Convert questions to #{dialect} SELECT-only queries. Return ONLY SQL, no markdown. Schema:\n#{schema_text}"

      body = %{model: model, messages: [%{role: "system", content: system_prompt}, %{role: "user", content: question}], temperature: 0.1, max_tokens: 500}

      case call_llm(api_url, api_key, body) do
        {:ok, sql} ->
          sql = String.trim(sql)
          if GuardaWeb.QueryController.safe_query?(sql), do: {:ok, sql}, else: {:error, "Generated SQL failed safety check"}
        error -> error
      end
    end
  end

  defp format_schema(schema) when is_list(schema) do
    Enum.map_join(schema, "\n", fn t ->
      cols = (t[:columns] || []) |> Enum.map_join(", ", fn c -> "#{c[:name]}(#{c[:type]})" end)
      "TABLE #{t[:table]}: #{cols}"
    end)
  end
  defp format_schema(_), do: "No schema"

  defp call_llm(url, key, body) do
    headers = [{"authorization", "Bearer #{key}"}, {"content-type", "application/json"}]
    case Req.post(url, body: Jason.encode!(body), headers: headers) do
      {:ok, %{status: 200, body: resp}} when is_map(resp) ->
        content = resp |> Map.get("choices", []) |> List.first(%{}) |> get_in(["message", "content"])
        if content, do: {:ok, content |> String.replace(~r/```sql\s*/i, "") |> String.replace(~r/```\s*/, "") |> String.trim()}, else: {:error, "No LLM response"}
      {:ok, %{status: 200, body: _}} ->
        {:error, "Unexpected LLM response format"}
      {:ok, %{status: s}} -> {:error, "LLM API HTTP #{s}"}
      {:error, r} -> {:error, "LLM API error: #{inspect(r)}"}
    end
  end
end
