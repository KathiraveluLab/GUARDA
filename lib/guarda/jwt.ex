defmodule Guarda.JWT do
  @moduledoc """
  Proper JWT implementation using HMAC-SHA256 for signing and verification.

  Replaces the forgeable Phoenix.Token approach with a standards-compliant JWT
  that includes expiration, issuer validation, and issued-at timestamps.
  """

  @issuer "guarda"
  @default_max_age 86_400  # 24 hours in seconds

  @doc """
  Signs a payload into a JWT string.

  ## Options
    * `:max_age` - Token lifetime in seconds (default: 86400 = 24h)
  """
  def sign(payload, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, @default_max_age)
    now = System.system_time(:second)

    claims = %{
      "sub" => payload,
      "iss" => @issuer,
      "iat" => now,
      "exp" => now + max_age
    }

    header = %{"alg" => "HS256", "typ" => "JWT"}

    header_b64 = base64url_encode(Jason.encode!(header))
    claims_b64 = base64url_encode(Jason.encode!(claims))
    signing_input = "#{header_b64}.#{claims_b64}"

    signature = :crypto.mac(:hmac, :sha256, secret_key(), signing_input)
    signature_b64 = base64url_encode(signature)

    "#{signing_input}.#{signature_b64}"
  end

  @doc """
  Verifies a JWT string and returns the payload.

  Returns `{:ok, payload}` on success, `{:error, reason}` on failure.
  """
  def verify(token) when is_binary(token) do
    parts = String.split(token, ".", parts: 4)

    with [header_b64, claims_b64, signature_b64] when length(parts) == 3 <- parts,
         {:ok, _header} <- decode_segment(header_b64),
         {:ok, claims} <- decode_segment(claims_b64),
         :ok <- verify_signature(header_b64, claims_b64, signature_b64),
         :ok <- verify_expiration(claims),
         :ok <- verify_issuer(claims) do
      {:ok, claims["sub"]}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_), do: {:error, :invalid_token}

  # --- Private Helpers ---

  defp secret_key do
    GuardaWeb.Endpoint.config(:secret_key_base)
    |> binary_part(0, 32)
  end

  defp base64url_encode(data) do
    Base.url_encode64(data, padding: false)
  end

  defp decode_segment(segment) do
    case Base.url_decode64(segment, padding: false) do
      {:ok, json} -> Jason.decode(json)
      :error -> {:error, :invalid_encoding}
    end
  end

  defp verify_signature(header_b64, claims_b64, signature_b64) do
    signing_input = "#{header_b64}.#{claims_b64}"
    expected = :crypto.mac(:hmac, :sha256, secret_key(), signing_input)
    expected_b64 = base64url_encode(expected)

    if Plug.Crypto.secure_compare(expected_b64, signature_b64) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp verify_expiration(%{"exp" => exp}) do
    if System.system_time(:second) < exp do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp verify_expiration(_), do: {:error, :missing_expiration}

  defp verify_issuer(%{"iss" => @issuer}), do: :ok
  defp verify_issuer(_), do: {:error, :invalid_issuer}
end
