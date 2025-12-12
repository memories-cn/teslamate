defmodule TeslaMate.Repo.Migrations.AddTenantIdToDatabase do
  use Ecto.Migration

  def change do
    alter table(:cars) do
      add :tenant_id, :uuid
    end

    execute "UPDATE cars SET tenant_id = '34e9c0fb-adf4-448a-a463-0f9b7484076e' WHERE tenant_id IS NULL"

    execute "ALTER TABLE cars ALTER COLUMN tenant_id SET NOT NULL;"
    execute "CREATE UNIQUE INDEX cars_tenant_id_unique ON cars (tenant_id);"
    execute "CREATE INDEX idx_cars_tenant_id ON cars (tenant_id);"
  end

  def down do
    execute "DROP INDEX private.idx_cars_tenant_id;"
    execute "DROP INDEX private.cars_tenant_id_unique;"
    execute "ALTER TABLE cars DROP COLUMN IF EXISTS tenant_id;"
  end
end
