defmodule Guarda.JWTTest do
  use ExUnit.Case, async: true

  test "sign/1 and verify/1 round-trip correctly" do
    payload = %{"user_id" => "test_user", "role" => "admin"}

    token = Guarda.JWT.sign(payload)
    assert is_binary(token)
    assert String.contains?(token, ".")

    assert {:ok, decoded} = Guarda.JWT.verify(token)
    assert decoded == payload
  end

  test "verify/1 rejects expired tokens" do
    payload = "test_user"
    # Sign with 0 max_age to make it expire immediately
    token = Guarda.JWT.sign(payload, max_age: 0)

    # Wait a moment to ensure expiration
    :timer.sleep(1100)

    assert {:error, :token_expired} = Guarda.JWT.verify(token)
  end

  test "verify/1 rejects tampered tokens" do
    token = Guarda.JWT.sign("test_user")

    # Tamper with the payload
    [header, _payload, signature] = String.split(token, ".")
    tampered = "#{header}.#{Base.url_encode64("tampered", padding: false)}.#{signature}"

    assert {:error, _reason} = Guarda.JWT.verify(tampered)
  end

  test "verify/1 rejects invalid format" do
    assert {:error, :invalid_token} = Guarda.JWT.verify("not.a.valid.token.at.all")
    assert {:error, :invalid_token} = Guarda.JWT.verify("garbage")
    assert {:error, :invalid_token} = Guarda.JWT.verify(nil)
    assert {:error, :invalid_token} = Guarda.JWT.verify(123)
  end

  test "sign/2 respects custom max_age" do
    token = Guarda.JWT.sign("user", max_age: 3600)
    assert {:ok, "user"} = Guarda.JWT.verify(token)
  end
end
