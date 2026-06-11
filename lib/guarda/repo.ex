defmodule Guarda.Repo do
  use Ecto.Repo,
    otp_app: :guarda,
    adapter: Ecto.Adapters.Postgres
end
