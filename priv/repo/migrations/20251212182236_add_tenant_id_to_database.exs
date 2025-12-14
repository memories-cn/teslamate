defmodule TeslaMate.Repo.Migrations.AddTenantIdToDatabase do
  use Ecto.Migration

  @default_tenant_id "34e9c0fb-adf4-448a-a463-0f9b7484076e"

  def up do
    add_tenant_id_to_table(:cars)
    add_tenant_id_to_table(:positions)
    add_tenant_id_to_table(:drives)
    add_tenant_id_to_table(:states)
  end

  def down do
    remove_tenant_id_from_table(:cars)
    remove_tenant_id_from_table(:positions)
    remove_tenant_id_from_table(:drives)
    remove_tenant_id_from_table(:states)
  end

  defp add_tenant_id_to_table(table_name) do
    alter table(table_name) do
      add :tenant_id, :uuid
    end

    execute """
    UPDATE #{table_name}
    SET tenant_id = '#{@default_tenant_id}'
    WHERE tenant_id IS NULL
    """

    alter table(table_name) do
      modify :tenant_id, :uuid, null: false
    end

    create index(table_name, [:tenant_id])
  end

  defp remove_tenant_id_from_table(table_name) do
    drop_if_exists index(table_name, [:tenant_id])

    alter table(table_name) do
      remove :tenant_id
    end
  end
end
