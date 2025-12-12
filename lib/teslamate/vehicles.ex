defmodule TeslaMate.Vehicles do
  use Supervisor

  require Logger

  alias __MODULE__.Vehicle
  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Log.Car
  alias TeslaMate.Log

  @name __MODULE__

  def start_link(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    name = via_tuple(tenant_id)
    opts = Keyword.put(opts, :name, name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  # 动态进程名称：
  # {TeslaMate.Api, tenant_id}
  # Registry 会管理唯一性，不会冲突
  defp via_tuple(tenant_id) do
    {:via, Registry, {TeslaMate.Registry, {__MODULE__, tenant_id}}}
  end

  def list(tenant_id) do
    name = via_tuple(tenant_id)

    Supervisor.which_children(name)
    |> Task.async_stream(fn {_, pid, _, _} -> Vehicle.summary(pid) end,
      ordered: false,
      max_concurrency: 10,
      timeout: 5000
    )
    |> Enum.map(fn {:ok, vehicle} -> vehicle end)
    |> Enum.sort_by(fn %Vehicle.Summary{car: %Car{id: id}} -> id end)
  end

  def kill(tenant_id) do
    name = via_tuple(tenant_id)
    Logger.warning("Restarting #{name} supervisor")
    pid = Registry.whereis_name({TeslaMate.Registry, {__MODULE__, tenant_id}})

    case pid do
      :undefined ->
        :ok

      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
    end
  end

  def restart(tenant_id) do
    name = via_tuple(tenant_id)

    with :ok <- Supervisor.stop(name, :normal),
         :ok <- block_until_started(250) do
      :ok
    end
  end

  defdelegate summary(id), to: Vehicle
  defdelegate resume_logging(id), to: Vehicle
  defdelegate suspend_logging(id), to: Vehicle
  defdelegate subscribe_to_summary(id), to: Vehicle
  defdelegate subscribe_to_fetch(id), to: Vehicle

  # Callbacks

  @impl true
  def init(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)

    children =
      opts
      |> Keyword.get_lazy(:vehicles, fn -> list_vehicles!(tenant_id) end)
      |> Enum.map(
        &{Keyword.get(opts, :vehicle, Vehicle),
         [car: create_or_update!(&1, tenant_id), tenant_id: tenant_id]}
      )
      |> Enum.uniq_by(fn {_mod, opts} -> Keyword.get(opts, :car).id end)
      |> Enum.filter(fn {_mod, opts} -> Keyword.get(opts, :car).settings.enabled end)

    Supervisor.init(children,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end

  # Private

  defp block_until_started(0), do: {:error, :restart_failed}

  defp block_until_started(retries) when retries > 0 do
    with pid when is_pid(pid) <- Process.whereis(@name),
         true <- Process.alive?(pid) do
      :ok
    else
      _ ->
        Process.sleep(10)
        block_until_started(retries - 1)
    end
  end

  defp list_vehicles!(tenant_id) do
    case TeslaMate.Api.list_vehicles(tenant_id) do
      {:error, :not_signed_in} ->
        fallback_vehicles(tenant_id)

      {:error, reason} ->
        Logger.warning("Could not get vehicles: #{inspect(reason)}")
        fallback_vehicles(tenant_id)

      {:ok, []} ->
        fallback_vehicles(tenant_id)

      {:ok, vehicles} ->
        vehicles
    end
  end

  defp fallback_vehicles(tenant_id) do
    vehicles =
      Log.list_cars()
      |> Enum.filter(&(&1.tenant_id == tenant_id))
      |> Enum.map(fn %Car{eid: eid, vid: vid, vin: vin, name: name} ->
        %TeslaApi.Vehicle{id: eid, vin: vin, vehicle_id: vid, display_name: name}
      end)

    if vehicles != [] do
      Logger.warning("Using fallback vehicles:\n\n#{inspect(vehicles, pretty: true)}")
    end

    vehicles
  end

  def create_or_update!(%TeslaApi.Vehicle{} = vehicle, tenant_id) do
    unless is_nil(name = vehicle.display_name), do: Logger.info("Starting logger for '#{name}'")

    {:ok, car} =
      with nil <- Log.get_car_by(vin: vehicle.vin, tenant_id: tenant_id),
           nil <- Log.get_car_by(vid: vehicle.vehicle_id, tenant_id: tenant_id),
           nil <- Log.get_car_by(eid: vehicle.id, tenant_id: tenant_id) do
        settings =
          case Vehicle.identify(vehicle) do
            {:ok, %{model: m, trim_badging: trim_badging, marketing_name: marketing_name}}
            when m in ["S", "X"] and (trim_badging == nil or is_binary(marketing_name)) ->
              %CarSettings{suspend_min: 12}

            {:ok, %{model: m}} when m in ["3", "Y"] ->
              %CarSettings{suspend_min: 12}

            _ ->
              %CarSettings{}
          end

        %Car{settings: settings}
      end
      |> Car.changeset(%{
        name: vehicle.display_name,
        eid: vehicle.id,
        vid: vehicle.vehicle_id,
        vin: vehicle.vin,
        tenant_id: tenant_id
      })
      |> Log.create_or_update_car()

    car
  end
end
