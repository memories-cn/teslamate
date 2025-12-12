defmodule TeslaMate.Auth.Tokens do
  use Ecto.Schema

  import Ecto.Changeset

  alias TeslaMate.Vault.Encrypted

  @schema_prefix :private

  schema "tokens" do
    field :refresh, Encrypted.Binary, redact: true
    field :access, Encrypted.Binary, redact: true
    # 新增租户标识
    field :tenant_id, Ecto.UUID

    timestamps()
  end

  @doc false
  def changeset(tokens, attrs) do
    tokens
    # 添加 tenant_id
    |> cast(attrs, [:access, :refresh, :tenant_id])
    # 必填
    |> validate_required([:access, :refresh, :tenant_id])
    # 唯一性约束
    |> unique_constraint(:tenant_id, name: :tokens_tenant_id_unique)
  end
end
