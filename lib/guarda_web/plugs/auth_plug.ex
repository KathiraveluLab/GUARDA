defmodule GuardaWeb.AuthPlug do
  @moduledoc """
  Provides zero-latency API key verification via ETS, and acts as 
  the JWT interceptor for federated endpoints.
  """
  import Plug.Conn
  require Logger

  def init(default), do: default

  def call(conn, _opts) do
    api_key = get_req_header(conn, "x-api-key") |> List.first()

    if api_key do
      case Guarda.APIKeys.validate(api_key) do
        {:ok, claims} ->
          Logger.debug("User authenticated via ETS Cache: #{inspect(claims)}")
          assign(conn, :current_user, claims)

        {:error, :unauthorized} ->
          Logger.warning("Unauthorized API Key attempt.")
          conn |> send_resp(:unauthorized, "Unauthorized") |> halt()
      end
    else
      # Fallback to JWT handling if X-API-Key isn't present
      auth_header = get_req_header(conn, "authorization") |> List.first()

      if auth_header && String.starts_with?(auth_header, "Bearer ") do
        token = String.replace(auth_header, "Bearer ", "")

        # Real implementation using native Phoenix.Token (built on Plug.Crypto)
        # Prevents heavy external dependencies while ensuring strict cryptographic signatures
        case Phoenix.Token.verify(GuardaWeb.Endpoint, "guardian_auth", token, max_age: 86400) do
          {:ok, claims} ->
            Logger.debug("User authenticated via verified Phoenix.Token: #{inspect(claims)}")
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
end
