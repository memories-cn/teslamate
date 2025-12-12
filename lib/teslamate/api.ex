defmodule TeslaMate.Api do
  use GenServer

  require Logger

  alias ElixirSense.Log
  alias TeslaMate.Auth.Tokens
  alias TeslaMate.{Vehicles, Convert}
  alias TeslaApi.Auth

  alias Finch.Response

  import Core.Dependency, only: [call: 3, call: 2]

  defmodule State do
    @moduledoc """
    存储 Tesla API 服务的状态信息

    该结构体用于存储 Tesla API GenServer 的状态，包括认证信息、依赖项和定时器引用。
    """
    defstruct name: nil, tenant_id: nil, deps: %{}, refresh_timer: nil
  end

  @timeout :timer.minutes(2)

  # API

  def start_link(opts) do
    # 强制要求启动时必须提供 tenant_id，否则抛异常
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    # 构建进程在 Registry 中的注册名称
    name = via_tuple(tenant_id)
    # 不允许外部传 name，保证命名统一
    opts = Keyword.put(opts, :name, name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # 动态进程名称：
  # {TeslaMate.Api, tenant_id}
  # Registry 会管理唯一性，不会冲突
  defp via_tuple(tenant_id) do
    {:via, Registry, {TeslaMate.Registry, {__MODULE__, tenant_id}}}
  end

  ## State

  def list_vehicles(tenant_id) do
    with {:ok, auth} <- fetch_auth(tenant_id) do
      TeslaApi.Vehicle.list(auth)
      |> handle_result(auth, tenant_id)
    end
  end

  def get_vehicle(tenant_id, id) do
    with {:ok, auth} <- fetch_auth(tenant_id) do
      TeslaApi.Vehicle.get(auth, id)
      |> handle_result(auth, tenant_id)
    end
  end

  def get_vehicle_with_state(tenant_id, id) do
    with {:ok, auth} <- fetch_auth(tenant_id) do
      TeslaApi.Vehicle.get_with_state(auth, id)
      |> handle_result(auth, tenant_id)
    end
  end

  def stream(tenant_id, vid, receiver) do
    with {:ok, %Auth{} = auth} <- fetch_auth(tenant_id) do
      TeslaApi.Stream.start_link(auth: auth, vehicle_id: vid, receiver: receiver)
    end
  end

  ## Internals

  def signed_in?(tenant_id) do
    case fetch_auth(tenant_id) do
      {:error, :not_signed_in} -> false
      {:ok, _} -> true
    end
  end

  def sign_in(tenant_id, args)

  def sign_in(tenant_id, %Tokens{} = tokens) do
    name = via_tuple(tenant_id)

    case fetch_auth(tenant_id) do
      {:error, :not_signed_in} -> GenServer.call(name, {:sign_in, [tokens]}, @timeout)
      {:ok, %Auth{}} -> {:error, :already_signed_in}
    end
  end

  def sign_in(tenant_id, {email, password}) do
    name = via_tuple(tenant_id)

    case fetch_auth(tenant_id) do
      {:error, :not_signed_in} -> GenServer.call(name, {:sign_in, [email, password]}, @timeout)
      {:ok, %Auth{}} -> {:error, :already_signed_in}
    end
  end

  def sign_out(tenant_id) do
    name = ets_table_name(tenant_id)
    true = :ets.delete(name, :auth)
    :ok
  rescue
    _ in ArgumentError -> {:error, :not_signed_in}
  end

  # Callbacks

  @impl true
  def init(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    name = Keyword.get(opts, :name, via_tuple(tenant_id))

    # 创建租户级别的 ETS 表
    table_name = ets_table_name(tenant_id)
    :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true])

    # 安装租户级熔断器
    :fuse.install(fuse_name(tenant_id), {{:standard, 5, 10_000}, {:reset, :timer.minutes(1)}})

    deps = %{
      auth: Keyword.get(opts, :auth, TeslaMate.Auth),
      vehicles: Keyword.get(opts, :vehicles, Vehicles)
    }

    state = %State{
      name: name,
      tenant_id: tenant_id,
      deps: deps
    }

    # 使用租户 ID 查询 Token
    # 尝试获取并刷新认证令牌
    with {:ok, tokens} <- call(state.deps.auth, :get_tokens, [tenant_id]),
         restored_tokens = %Auth{
           token: tokens.access,
           refresh_token: tokens.refresh,
           expires_in: 10 * 60
         },
         {:ok, auth} <-
           refresh_tokens(restored_tokens) do
      # 将新的认证信息插入到ETS表中
      true = insert_auth(tenant_id, auth)
      # 保存新的认证信息
      :ok = call(state.deps.auth, :save, [tenant_id, auth])
      # 安排下次刷新令牌的时间
      {:ok, state} = schedule_refresh(auth, state)
      # 重置熔断器
      :ok = :fuse.reset(fuse_name(tenant_id))
      {:ok, state}
    else
      # 如果获取或刷新令牌失败，则保持当前状态
      {:error, reason} ->
        Logger.warning("Failed to sign in: #{inspect(reason, pretty: true)}")
        {:ok, state}

      _ ->
        {:ok, state}
    end

    # name = Keyword.fetch!(opts, :name)

    # :ok =
    #   :fuse.install(
    #     fuse_name(name),
    #     {{:standard, 5, :timer.minutes(10)}, {:reset, :timer.hours(9999)}}
    #   )

    # ^name = :ets.new(name, [:named_table, :set, :public, read_concurrency: true])
    # state = %State{name: name, deps: deps}

    # # 初始化认证状态：尝试从存储中恢复并刷新访问令牌
    # state =
    #   case call(deps.auth, :get_tokens) do
    #     # 当成功获取到有效的访问令牌和刷新令牌时
    #     %Tokens{access: at, refresh: rt} when is_binary(at) and is_binary(rt) ->
    #       # 构造临时认证对象，设置默认过期时间为10分钟
    #       restored_tokens = %Auth{token: at, refresh_token: rt, expires_in: 10 * 60}

    #       # 尝试刷新令牌
    #       {:ok, state} =
    #         case refresh_tokens(restored_tokens) do
    #           # 刷新成功：保存新令牌并安排下一次刷新
    #           {:ok, refreshed_tokens} ->
    #             :ok = call(deps.auth, :save, [refreshed_tokens])
    #             true = insert_auth(name, refreshed_tokens)
    #             schedule_refresh(refreshed_tokens, state)

    #           # 刷新失败：记录警告日志，仍使用原令牌并安排刷新
    #           {:error, reason} ->
    #             Logger.warning("Token refresh failed: #{inspect(reason, pretty: true)}")
    #             true = insert_auth(name, restored_tokens)
    #             schedule_refresh(restored_tokens, state)
    #         end

    #       state

    #     # 无法解密API令牌时记录警告
    #     %Tokens{access: :error, refresh: :error} ->
    #       Logger.warning("Could not decrypt API tokens!")
    #       state

    #     # 其他情况保持原状态不变
    #     _ ->
    #       state
    #   end

    # {:ok, state}
  end

  @doc """
  处理 Tesla 账户登录请求。

  此函数支持多种认证方式，包括回调函数认证和令牌刷新两种方式。
  根据传入参数的不同类型，会选择相应的认证路径执行认证操作。

  ## 参数

  - `{:sign_in, args}` - 请求元组，其中 args 是认证所需的参数列表
  - `_` - 来自 GenServer 的原始请求参数（未使用）
  - `%State{} = state` - 当前服务器状态

  ## 返回值

  返回一个标准的 GenServer handle_call 响应元组，格式为 {:reply, response, new_state}，
  其中 response 可能是:
  - :ok - 认证成功
  - {:ok, {:captcha, captcha, wrapped_callback}} - 需要验证码验证
  - {:ok, {:mfa, devices, wrapped_callback}} - 需要多因素认证
  - {:error, error} - 认证过程中发生错误
  """
  @impl true
  def handle_call({:sign_in, args}, _, %State{} = state) do
    # 处理登录请求，支持多种认证方式
    # 根据参数类型选择不同的认证路径：
    # 1. 如果提供了回调函数，则调用该回调函数进行认证
    # 2. 如果提供了Tokens结构体，则直接刷新令牌
    case args do
      [args, callback] when is_function(callback) -> apply(callback, args)
      [%Tokens{} = t] -> Auth.refresh(%Auth{token: t.access, refresh_token: t.refresh})
    end
    |> case do
      # 认证成功，保存认证信息并更新相关状态
      {:ok, %Auth{} = auth} ->
        true = insert_auth(state.name, auth)
        :ok = call(state.deps.auth, :save, [auth])
        :ok = call(state.deps.vehicles, :restart)
        {:ok, state} = schedule_refresh(auth, state)
        :ok = :fuse.reset(fuse_name(state.name))

        {:reply, :ok, state}

      # 需要验证码验证，包装回调函数以便后续处理
      {:ok, {:captcha, captcha, callback}} ->
        # 包装回调函数，使其能够在提供验证码后继续登录流程
        wrapped_callback = fn captcha_code ->
          GenServer.call(state.name, {:sign_in, [[captcha_code], callback]}, @timeout)
        end

        {:reply, {:ok, {:captcha, captcha, wrapped_callback}}, state}

      # 需要多因素认证，包装回调函数以便后续处理
      {:ok, {:mfa, devices, callback}} ->
        # 包装回调函数，使其能够在提供MFA设备和密码后继续登录流程
        wrapped_callback = fn device_id, mfa_passcode ->
          GenServer.call(state.name, {:sign_in, [[device_id, mfa_passcode], callback]}, @timeout)
        end

        {:reply, {:ok, {:mfa, devices, wrapped_callback}}, state}

      # 登录过程出现错误，返回错误信息
      {:error, %TeslaApi.Error{} = e} ->
        {:reply, {:error, e}, state}
    end
  end

  @impl true
  def handle_info(:refresh_auth, %State{tenant_id: tenant_id} = state) do
    # 获取当前认证信息以刷新访问令牌
    case fetch_auth(tenant_id) do
      {:ok, tokens} ->
        Logger.info("[Tenant #{tenant_id}] Refreshing access token ...")

        # 尝试刷新访问令牌
        case Auth.refresh(tokens) do
          {:ok, refreshed_tokens} ->
            # 刷新成功：保存新令牌并安排下次刷新
            true = insert_auth(tenant_id, refreshed_tokens)
            :ok = call(state.deps.auth, :save, [tenant_id, refreshed_tokens])
            {:ok, state} = schedule_refresh(refreshed_tokens, state)
            :ok = :fuse.reset(fuse_name(tenant_id))
            {:noreply, state}

          {:error, reason} ->
            # 刷新失败：记录错误日志并安排5分钟后重试
            Logger.warning("[Tenant #{tenant_id}] Token refresh failed: #{inspect(reason)}")
            Logger.warning("[Tenant #{tenant_id}] Retrying in 5 minutes...")

            # 取消之前的刷新计时器（如果存在）
            if is_reference(state.refresh_timer), do: Process.cancel_timer(state.refresh_timer)
            # 设置5分钟后重新尝试刷新令牌
            refresh_timer = Process.send_after(self(), :refresh_auth, :timer.minutes(5))

            {:noreply, %State{state | refresh_timer: refresh_timer}}
        end

      {:error, reason} ->
        # 无法获取认证信息：记录警告日志并保持当前状态
        Logger.warning("[Tenant #{tenant_id}] Cannot refresh access token: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.info("#{__MODULE__} / unhandled message: #{inspect(msg, pretty: true)}")
    {:noreply, state}
  end

  ## Private

  defp refresh_tokens(%Auth{} = tokens) do
    case Application.get_env(:teslamate, :disable_token_refresh, false) do
      true ->
        Logger.info("Token refresh is disabled")
        {:ok, tokens}

      false ->
        with {:ok, %Auth{} = refresh_tokens} <- Auth.refresh(tokens) do
          Logger.info("Refreshed api tokens")
          {:ok, refresh_tokens}
        end
    end
  end

  defp schedule_refresh(%Auth{} = auth, %State{} = state) do
    ms =
      auth.expires_in
      |> Kernel.*(0.75)
      |> round()
      |> :timer.seconds()

    duration =
      ms
      |> div(1000)
      |> Convert.sec_to_str()
      |> Enum.reject(&String.ends_with?(&1, "s"))
      |> Enum.join(" ")

    Logger.info("Scheduling token refresh in #{duration}")

    if is_reference(state.refresh_timer), do: Process.cancel_timer(state.refresh_timer)
    refresh_timer = Process.send_after(self(), :refresh_auth, ms)

    {:ok, %State{state | refresh_timer: refresh_timer}}
  end

  @doc """
  根据租户ID生成ETS表名

  ## 参数

  - `tenant_id`: 租户唯一标识符

  ## 返回值

  返回一个原子类型的ETS表名，格式为`:api_{tenant_id}`
  """
  defp ets_table_name(tenant_id) do
    String.to_atom("api_#{tenant_id}")
  end

  @doc """
  将认证信息插入到ETS表中

  ## 参数

  - `tenant_id`: 租户唯一标识符，用于确定ETS表
  - `auth`: 包含认证信息的Auth结构体

  ## 返回值

  返回`:ets.insert/2`函数的结果
  """
  defp insert_auth(tenant_id, %Auth{} = auth) do
    table_name = ets_table_name(tenant_id)
    :ets.insert(table_name, {:auth, auth})
  end

  @doc """
  从ETS表中获取认证信息

  ## 参数

  - `tenant_id`: 租户唯一标识符，用于确定ETS表

  ## 返回值

  - `{:ok, auth}`: 成功获取认证信息
  - `{:error, :not_signed_in}`: 未找到认证信息或发生ArgumentError异常
  """
  defp fetch_auth(tenant_id) do
    table_name = ets_table_name(tenant_id)

    case :ets.lookup(table_name, :auth) do
      [auth: %Auth{} = auth] -> {:ok, auth}
      [] -> {:error, :not_signed_in}
    end

    # 如果在执行过程中发生了 ArgumentError 异常（例如 ETS 表不存在），则会被 rescue 捕获，并返回 {:error, :not_signed_in}
  rescue
    _ in ArgumentError -> {:error, :not_signed_in}
  end

  defp handle_result(result, auth, name) do
    case result do
      {:error, %TeslaApi.Error{reason: :unauthorized}} ->
        :ok = :fuse.melt(fuse_name(name))

        case :fuse.ask(fuse_name(name), :sync) do
          :blown ->
            true = :ets.delete(name, :auth)
            {:error, :not_signed_in}

          :ok ->
            send(name, :refresh_auth)
            {:error, :unauthorized}
        end

      {:error, %TeslaApi.Error{reason: reason, env: %Response{status: status, body: body}}} ->
        Logger.error("TeslaApi.Error / #{status} – #{inspect(body, pretty: true)}")
        {:error, reason}

      {:error, %TeslaApi.Error{reason: :too_many_request, message: retry_after}} ->
        Logger.warning("TeslaApi.Error / :too_many_request #{retry_after}")
        {:error, :too_many_request, retry_after}

      {:error, %TeslaApi.Error{reason: reason, message: msg}} ->
        if is_binary(msg) and msg != "", do: Logger.warning("TeslaApi.Error / #{msg}")
        {:error, reason}

      {:ok, vehicles} when is_list(vehicles) ->
        vehicles =
          vehicles
          |> Task.async_stream(&preload_vehicle(&1, auth), timeout: 32_500)
          |> Enum.map(fn {:ok, vehicle} -> vehicle end)

        {:ok, vehicles}

      {:ok, %TeslaApi.Vehicle{} = vehicle} ->
        {:ok, vehicle}
    end
  end

  defp preload_vehicle(%TeslaApi.Vehicle{state: "online", id: id} = vehicle, auth) do
    case TeslaApi.Vehicle.get_with_state(auth, id) do
      {:ok, %TeslaApi.Vehicle{} = vehicle} ->
        vehicle

      {:error, reason} ->
        Logger.warning("TeslaApi.Error / #{inspect(reason, pretty: true)}")
        vehicle
    end
  end

  defp preload_vehicle(%TeslaApi.Vehicle{} = vehicle, _state), do: vehicle

  defp fuse_name(tenant_id) do
    String.to_atom("api_auth_#{tenant_id}")
  end
end
