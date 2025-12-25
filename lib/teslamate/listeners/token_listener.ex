defmodule TeslaMate.Listeners.TokenListener do
  use GenServer
  require Logger
  import Ecto.Query, only: [from: 2]

  alias TeslaMate.{Repo, Auth}
  alias TeslaMate.Auth.Tokens

  defmodule State do
    defstruct [:pid, :ref, :channel, :tenant_manager]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # 从TeslaMate.Repo获取数据库连接参数
    config = Repo.config()
    
    hostname = config[:hostname] || System.get_env("DATABASE_HOST", "localhost")
    username = config[:username] || System.get_env("DATABASE_USER", "teslamate")
    password = config[:password] || System.get_env("DATABASE_PASS", "123456")
    database = config[:database] || System.get_env("DATABASE_NAME", "teslamate_dev")
    port = config[:port] || String.to_integer(System.get_env("DATABASE_PORT", "5432"))

    # 启动Postgrex.Notifications连接
    case Postgrex.Notifications.start_link(
           hostname: hostname,
           username: username,
           password: password,
           database: database,
           port: port
         ) do
      {:ok, pid} ->
        # 监听token_events通道
        ref = Postgrex.Notifications.listen!(pid, "token_events")

        state = %State{
          pid: pid,
          ref: ref,
          channel: "token_events",
          tenant_manager: TeslaMate.Tenants
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start TokenListener: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:notification, _pid, ref, channel, payload}, 
                  %State{ref: ref, channel: channel} = state) do
    case Jason.decode(payload) do
      {:ok, %{"action" => action, "id" => id, "tenant_id" => tenant_id}} ->
        Logger.info("Received #{action} notification for token id: #{id}, tenant_id: #{tenant_id}")

        case action do
          "INSERT" ->
            handle_token_insert(tenant_id)

          "DELETE" ->
            handle_token_delete(tenant_id)

          _ ->
            Logger.warning("Unknown action: #{action}")
        end

      error ->
        Logger.error("Failed to parse notification payload: #{inspect(error)}")
    end

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  # Private functions

  defp handle_token_insert(tenant_id) do
    Logger.info("Handling new token for tenant: #{tenant_id}")

    # 尝试启动对应的租户服务
    case TeslaMate.Tenants.start_tenant(tenant_id) do
      {:ok, _pid} ->
        Logger.info("Started tenant processes for #{tenant_id}")

      {:error, {:already_started, _pid}} ->
        Logger.info("Tenant #{tenant_id} already started")

      {:error, reason} ->
        Logger.error("Failed to start tenant #{tenant_id}: #{inspect(reason)}")
    end
  end

  defp handle_token_delete(tenant_id) do
    Logger.info("Handling deleted token for tenant: #{tenant_id}")

    # 尝试停止对应的租户服务
    case TeslaMate.Tenants.stop_tenant(tenant_id) do
      :ok ->
        Logger.info("Stopped tenant processes for #{tenant_id}")

      {:error, :not_found} ->
        Logger.info("Tenant #{tenant_id} was not running")

      {:error, reason} ->
        Logger.error("Failed to stop tenant #{tenant_id}: #{inspect(reason)}")
    end
  end
end
