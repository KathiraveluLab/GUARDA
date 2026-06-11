defmodule GuardaWeb.PageController do
  use GuardaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
