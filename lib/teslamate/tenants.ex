defmodule TeslaMate.Tenants do
  use Supervisor

  require Logger
  import Ecto.Query, warn: false

  alias TeslaMate.{Auth, Repo}
  alias TeslaMate.Auth.Tokens

  @name __MODULE__

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end

  def start_tenant(tenant_id) do
    spec = tenant_spec(tenant_id)
    Supervisor.start_child(@name, spec)
  end

  def stop_tenant(tenant_id) do
    Supervisor.terminate_child(@name, tenant_id)
    Supervisor.delete_child(@name, tenant_id)
  end

  def restart_tenant(tenant_id) do
    with :ok <- stop_tenant(tenant_id),
         {:ok, _} <- start_tenant(tenant_id) do
      :ok
    end
  end

  def list_tenants do
    Supervisor.which_children(@name)
    |> Enum.map(fn {tenant_id, _pid, _type, _modules} -> tenant_id end)
  end

  @impl true
  def init(_opts) do
    # Auth.save("34e9c0fb-adf4-448a-a463-0f9b7484076e", %{
    #   token:
    #     "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImNKbVdVTUdWLWpDcl9xWDI4am90UkViX2h1WSJ9.eyJpc3MiOiJodHRwczovL2F1dGgudGVzbGEuY24vb2F1dGgyL3YzIiwiYXpwIjoib3duZXJhcGkiLCJzdWIiOiIxZDllYTZmMS0wMjgxLTQyYTAtOTQxNC02NzExNDA1NGI2NGUiLCJhdWQiOlsiaHR0cHM6Ly9vd25lci1hcGkudGVzbGFtb3RvcnMuY29tLyIsImh0dHBzOi8vYXV0aC50ZXNsYS5jbi9vYXV0aDIvdjMvdXNlcmluZm8iXSwic2NwIjpbIm9wZW5pZCIsImVtYWlsIiwib2ZmbGluZV9hY2Nlc3MiXSwiYW1yIjpbXSwiZXhwIjoxNzY1MzgxMTkwLCJpYXQiOjE3NjUzNTIzOTAsIm91X2NvZGUiOiJDTiIsImxvY2FsZSI6bnVsbH0.DucWxD3awB64JiRRPC885X0WVmNUsbG1eqfESVvYbDuZ3gh_AxswPm7rP9j5rD1VDb5QHN96tBdGt30CjgpWjGJ3vKZdiGU_NCc55B8SpvAdcXFnan148HaLRdwNqdgEWBmUtQnFx12q8nb-T9MP54oecWwLks4QZ8gr1JHg1hF7SMachr56CUmvssKbRMuQzgON8npeI2g7oFlHbdwRacCegJAtiFtmO7Ta71ltpAMuw6XmkzOOPQCZ994h3g0YDd6LAZq5khI33lXDVPLfvjM9TJfv5JCF6H-sGiZBwlHaFvjoVndFnADkX6mM9GQ9ZUQuJ0JEh_xw05tHt-yszQ",
    #   refresh_token:
    #     "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImNKbVdVTUdWLWpDcl9xWDI4am90UkViX2h1WSJ9.eyJpc3MiOiJodHRwczovL2F1dGgudGVzbGEuY24vb2F1dGgyL3YzIiwic2NwIjpbIm9wZW5pZCIsIm9mZmxpbmVfYWNjZXNzIl0sImF1ZCI6Imh0dHBzOi8vYXV0aC50ZXNsYS5jbi9vYXV0aDIvdjMvdG9rZW4iLCJzdWIiOiIxZDllYTZmMS0wMjgxLTQyYTAtOTQxNC02NzExNDA1NGI2NGUiLCJkYXRhIjp7InYiOiIxIiwiYXVkIjoiaHR0cHM6Ly9vd25lci1hcGkudGVzbGFtb3RvcnMuY29tLyIsInN1YiI6IjFkOWVhNmYxLTAyODEtNDJhMC05NDE0LTY3MTE0MDU0YjY0ZSIsInNjcCI6WyJvcGVuaWQiLCJvZmZsaW5lX2FjY2VzcyJdLCJhenAiOiJvd25lcmFwaSIsImFtciI6WyJwd2QiXSwiYXV0aF90aW1lIjoxNzY1MzUyMzkwfSwiaWF0IjoxNzY1MzUyMzkwfQ.YIQREONEMBog0Rd2QJWh9kcPBiGnFfIzv3DOuNBJeTb-IcKJg28XBg_0eOAPBUrSg5m4OTp4Ln9XkZb7bVHG9qJ7HrOYXPMrbZpOQpU4HhoflKFSbg3_l5HdVwy5qTY1TSl-HsmHqpQmfhqPCQwZpC_6GgHNM1iiV_UBpmcJkcJmSOmGX_4nmOEh_3mkI44QUYA4Uk9NwrN5Y7oDsTBWkThSDN8Z5mhe-eRjc_QT_f0eKoEDHO63YMqNrHbpC-Ma6yTIrboT8ikmosgG17HlbQOWylQHiHEAC5HEZ35TacdYBLRmvA_dDxS0oj_b0QfcL747dfkNEwVgA8s4tdrEyQ"
    # })

    # 发现所有有效的租户
    tenants = list_active_tenants()

    children =
      tenants
      |> Enum.map(&tenant_spec/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private

  defp tenant_spec(tenant_id) do
    %{
      id: tenant_id,
      start: {
        Supervisor,
        :start_link,
        [
          [
            {TeslaMate.Api, [tenant_id: tenant_id]},
            {TeslaMate.Vehicles, [tenant_id: tenant_id]}
          ],
          [
            strategy: :one_for_one,
            name: {:via, Registry, {TeslaMate.Registry, {TeslaMate.Tenant, tenant_id}}}
          ]
        ]
      },
      type: :supervisor,
      restart: :permanent
    }
  end

  defp list_active_tenants do
    from(t in Tokens,
      # where: t.updated_at > ago(30, "day") and is_nil(t.deleted_at),
      select: t.tenant_id
    )
    |> Repo.all()
    |> Enum.uniq()
  end
end
