defmodule TeslaMate.Repo.Migrations.TokenInsertDeleteTrigger do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION notify_token_insert_delete()
    RETURNS trigger AS $$
    DECLARE
      payload json;
    BEGIN
      payload = json_build_object(
        'action', TG_OP,          -- INSERT / DELETE
        'id', COALESCE(NEW.id, OLD.id),
        'tenant_id', COALESCE(NEW.tenant_id, OLD.tenant_id)
      );

      PERFORM pg_notify('token_events', payload::text);

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    DROP TRIGGER IF EXISTS token_insert_delete_trigger ON private.tokens;
    """)

    execute("""
    CREATE TRIGGER token_insert_delete_trigger
    AFTER INSERT OR DELETE
    ON private.tokens
    FOR EACH ROW
    EXECUTE FUNCTION notify_token_insert_delete();
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS token_insert_delete_trigger ON private.tokens;
    """)

    execute("""
    DROP FUNCTION IF EXISTS notify_token_insert_delete();
    """)
  end
end
