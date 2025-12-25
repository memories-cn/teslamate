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
