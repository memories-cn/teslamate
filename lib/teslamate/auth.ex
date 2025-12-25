defmodule TeslaMate.Auth do
  @moduledoc """
  认证模块，用于管理访问令牌和刷新令牌的存储与检索。
  """

  import Ecto.Query, warn: false
  require Logger

  alias TeslaMate.Repo

  ### Tokens

  alias TeslaMate.Auth.Tokens

  @doc """
  创建一个令牌变更集。

  ## 参数
  - attrs: 包含令牌属性的映射，默认为空映射

  ## 返回值
  返回一个 Tokens 变更集
  """
  def change_tokens(attrs \\ %{}) do
    %Tokens{} |> Tokens.changeset(attrs)
  end

  @doc """
  检查是否可以解密指定租户的令牌。

  ## 参数
  - tenant_id: 租户ID

  ## 返回值
  如果可以解密令牌或没有令牌则返回true，否则返回false
  """
  def can_decrypt_tokens?(tenant_id) do
    case get_tokens(tenant_id) do
      %Tokens{} = tokens ->
        is_binary(tokens.access) and is_binary(tokens.refresh)

      nil ->
        true
    end
  end

  @doc """
  获取指定租户的令牌。

  ## 参数
  - tenant_id: 租户ID

  ## 返回值
  返回 Tokens 结构体或 nil（如果未找到）
  """
  def get_tokens(tenant_id) do
    case Repo.one(from t in Tokens, where: t.tenant_id == ^tenant_id) do
      nil ->
        {:error, :not_found}

      tokens ->
        {:ok, %Tokens{} = tokens}
    end
  end

  @doc """
  保存指定租户的访问令牌和刷新令牌。

  ## 参数
  - tenant_id: 租户ID
  - tokens_map: 包含 :token 和 :refresh_token 键的映射

  ## 返回值
  成功时返回 :ok，失败时返回错误元组
  """
  def save(tenant_id, %{token: access, refresh_token: refresh}) do
    attrs = %{access: access, refresh: refresh, tenant_id: tenant_id}

    maybe_created_or_updated =
      case get_tokens(tenant_id) do
        {:error, :not_found} -> create_tokens(attrs)
        {:ok, tokens} -> update_tokens(tokens, attrs)
      end

    with {:ok, _tokens} <- maybe_created_or_updated do
      :ok
    end
  end

  # 创建新令牌记录
  defp create_tokens(attrs) do
    %Tokens{}
    |> Tokens.changeset(attrs)
    |> Repo.insert()
  end

  # 更新现有令牌记录
  defp update_tokens(%Tokens{} = tokens, attrs) do
    tokens
    |> Tokens.changeset(attrs)
    |> Repo.update()
  end
end
