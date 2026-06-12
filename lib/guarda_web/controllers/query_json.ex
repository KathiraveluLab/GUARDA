defmodule GuardaWeb.QueryJSON do
  @moduledoc """
  JSON view for the Query API responses.
  Provides consistent response formatting across all query endpoints.
  """

  def render("success.json", %{data: data}) do
    %{
      status: "success",
      data: data
    }
  end

  def render("error.json", %{error: error}) do
    %{
      status: "error",
      error: error
    }
  end
end
