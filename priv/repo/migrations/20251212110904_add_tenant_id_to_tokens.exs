defmodule TeslaMate.Repo.Migrations.AddTenantIdToTokens do
  use Ecto.Migration

  def change do
    alter table(:tokens, prefix: "private") do
      add :tenant_id, :uuid
    end

    execute "UPDATE private.tokens SET tenant_id = '34e9c0fb-adf4-448a-a463-0f9b7484076e' WHERE tenant_id IS NULL"
    execute "ALTER TABLE private.tokens ALTER COLUMN tenant_id SET NOT NULL;"
    execute "CREATE UNIQUE INDEX tokens_tenant_id_unique ON private.tokens (tenant_id);"
    execute "CREATE INDEX idx_tokens_tenant_id ON private.tokens (tenant_id);"
  end

  def down do
    execute "DROP INDEX private.idx_tokens_tenant_id;"
    execute "DROP INDEX private.tokens_tenant_id_unique;"
    execute "ALTER TABLE private.tokens DROP COLUMN IF EXISTS tenant_id;"
  end
end
