defmodule GuardaWeb.AuthPlug do
  @moduledoc """
  Provides zero-latency API key verification via ETS, and acts as
  the JWT interceptor for federated endpoints.

  Authentication priority:
  1. X-API-Key header - validated against ETS cache
  2. Authorization: Bearer <jwt> - verified using Guarda.JWT (HMAC-SHA256)

  Also extracts X-Tenant-ID for multi-tenancy scoping.
  """
  import Plug.Conn
  require Logger

  def init(default), do: default

  def call(conn, _opts) do
    # Extract tenant context
    conn = assign(conn, :tenant_id, Guarda.Tenant.extract_tenant(conn))

    api_key = get_req_header(conn, "x-api-key") |> List.first()

    if api_key do
      case Guarda.APIKeys.validate(api_key) do
        {:ok, claims} ->
          user_id = extract_user_id(claims)
          Logger.debug("Authenticated via API key: user=#{user_id}")
          assign(conn, :current_user, claims)

        {:error, :unauthorized} ->
          Logger.warning("Unauthorized API Key attempt.")
          conn |> send_resp(:unauthorized, "Unauthorized") |> halt()
      end
    else
      auth_header = get_req_header(conn, "authorization") |> List.first()

      if auth_header && String.starts_with?(auth_header, "Bearer ") do
        token = String.replace_prefix(auth_header, "Bearer ", "")

        case Guarda.JWT.verify(token) do
          {:ok, claims} ->
            user_id = extract_user_id(claims)
            Logger.debug("Authenticated via JWT: user=#{user_id}")
            assign(conn, :current_user, claims)

          {:error, reason} ->
            Logger.warning("Token validation failed: #{inspect(reason)}")
            conn |> send_resp(:unauthorized, "Invalid or Expired Token") |> halt()
        end
      else
        conn |> send_resp(:unauthorized, "Missing Authorization Header or API Key") |> halt()
      end
    end
  end

  defp extract_user_id(claims) when is_map(claims) do
    Map.get(claims, "user_id", Map.get(claims, :user_id, "unknown"))
  end

  defp extract_user_id(claims) when is_binary(claims), do: claims
  defp extract_user_id(_), do: "unknown"
end
