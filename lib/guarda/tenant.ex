defmodule Guarda.Tenant do
  @moduledoc """
  Multi-tenancy context module.

  Provides tenant isolation by scoping providers, API keys, and audit logs
  by `org_id`. Tenants are identified via the `X-Tenant-ID` header.
  """

  @doc """
  Extracts the tenant/org ID from the connection.
  Returns `nil` if no tenant header is present (single-tenant mode).
  """
  def extract_tenant(conn) do
    Plug.Conn.get_req_header(conn, "x-tenant-id") |> List.first()
  end

  @doc """
  Scopes a query or operation to a specific tenant.
  Returns a map with tenant context that can be passed to other modules.
  """
  def tenant_context(org_id) do
    %{
      org_id: org_id,
      scoped: org_id != nil
    }
  end

  @doc """
  Validates that a user has access to the requested tenant.
  In a full implementation, this would check against a database of tenant memberships.
  """
  def authorize_tenant(user_claims, org_id) do
    user_org = get_user_org(user_claims)

    cond do
      org_id == nil -> :ok
      user_org == org_id -> :ok
      user_org == "admin" -> :ok  # Admin users can access any tenant
      true -> {:error, :forbidden}
    end
  end

  defp get_user_org(claims) when is_map(claims) do
    Map.get(claims, "org_id", Map.get(claims, :org_id))
  end

  defp get_user_org(_), do: nil
end
