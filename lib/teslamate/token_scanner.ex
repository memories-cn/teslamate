defmodule TeslaMate.TokenScanner do
  use GenServer

  require Logger
  import Ecto.Query, only: [from: 2]

  alias TeslaMate.Auth.Tokens
  alias TeslaMate.Repo
  alias TeslaMate.Tenants

  @default_scan_interval :timer.minutes(5)

  defmodule State do
    defstruct [:timer_ref, :interval]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_scan do
    GenServer.call(__MODULE__, :force_scan)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_scan_interval)

    # 立即发送第一个扫描消息
    send(self(), :scan_tokens)

    {:ok, %State{interval: interval}}
  end

  @impl true
  def handle_call(:force_scan, _from, state) do
    scan_tokens(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:scan_tokens, %State{interval: interval} = state) do
    new_state = scan_tokens(state)

    # 安排下一次扫描
    timer_ref = Process.send_after(self(), :scan_tokens, interval)

    {:noreply, %State{new_state | timer_ref: timer_ref}}
  end

  # Private Functions

  defp scan_tokens(%State{} = state) do
    Logger.debug("Starting token table scan...")

    try do
      # 获取所有租户ID
      tenant_ids =
        Repo.all(from(t in Tokens, select: t.tenant_id))
        |> Enum.uniq()

      Logger.debug("Found #{length(tenant_ids)} tenants in tokens table")

      # 获取已经启动的租户列表
      active_tenants = Tenants.list_tenants()

      # 查找新的租户（存在于tokens表但尚未启动的）
      new_tenants = tenant_ids -- active_tenants

      # 查找需要停止的租户（已启动但不再存在于tokens表中的）
      tenants_to_stop = active_tenants -- tenant_ids

      Logger.info(
        "[token_scanner] Found #{length(new_tenants)} new tenant(s), readying for starting tenant processes"
      )

      # 为新租户启动Tenants子进程
      Enum.each(new_tenants, fn tenant_id ->
        Logger.info("Detected new tenant: #{tenant_id}, starting tenant processes")

        case Tenants.start_tenant(tenant_id) do
          {:ok, _pid} ->
            Logger.info("Successfully started tenant processes for #{tenant_id}")

          {:error, {:already_started, _pid}} ->
            Logger.info("Tenant #{tenant_id} already started")

          {:error, reason} ->
            Logger.error("Failed to start tenant #{tenant_id}: #{inspect(reason)}")
        end
      end)

      Logger.info("[token_scanner] Found #{length(tenants_to_stop)} tenant(s) need to stop")
      # 停止不再需要的租户
      Enum.each(tenants_to_stop, fn tenant_id ->
        Logger.info("Stopping tenant: #{tenant_id}, not found in tokens table")

        case Tenants.stop_tenant(tenant_id) do
          :ok ->
            Logger.info("Successfully stopped tenant processes for #{tenant_id}")

          {:error, reason} ->
            Logger.error("Failed to stop tenant #{tenant_id}: #{inspect(reason)}")
        end
      end)

      state
    rescue
      e ->
        Logger.error("Error scanning tokens: #{inspect(e)}")
        state
    end
  end
end
