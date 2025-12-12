# 驾驶记录表（Drives）结构

<cite>
**本文档引用的文件**
- [drive.ex](file://lib/teslamate/log/drive.ex)
- [car.ex](file://lib/teslamate/log/car.ex)
- [position.ex](file://lib/teslamate/log/position.ex)
- [log.ex](file://lib/teslamate/log.ex)
- [20190812191616_rename_trips_to_drives.exs](file://priv/repo/migrations/20190812191616_rename_trips_to_drives.exs)
- [20191003130650_add_start_and_end_position_to_drives.exs](file://priv/repo/migrations/20191003130650_add_start_and_end_position_to_drives.exs)
- [20190913175011_add_rated_range_to_drives.exs](file://priv/repo/migrations/20190913175011_add_rated_range_to_drives.exs)
- [20190821155748_drop_consumption_columns.exs](file://priv/repo/migrations/20190821155748_drop_consumption_columns.exs)
- [20200203120311_cascade_delete.exs](file://priv/repo/migrations/20200203120311_cascade_delete.exs)
- [20200410112005_database_efficiency_improvements.exs](file://priv/repo/migrations/20200410112005_database_efficiency_improvements.exs)
</cite>

## 目录
1. [引言](#引言)
2. [Drives表字段设计](#drives表字段设计)
3. [与Cars表的外键关联](#与cars表的外键关联)
4. [与Positions表的连接方式](#与positions表的连接方式)
5. [efficiency与consumption_kWh_100km的计算逻辑](#efficiency与consumption_kwh_100km的计算逻辑)
6. [驾驶行程的开始与结束判定机制](#驾驶行程的开始与结束判定机制)

## 引言
Drives表是TeslaMate系统中用于存储车辆驾驶行程的核心数据表。该表记录了每次驾驶的关键性能指标，包括时间、距离、能耗、速度等信息，并通过外键与Cars表和Positions表建立关联，形成完整的驾驶数据分析体系。本文档将深入解析Drives表的结构设计、字段含义、关联关系以及相关计算逻辑。

## Drives表字段设计
Drives表存储了每次驾驶行程的汇总信息，其核心字段包括：

- **start_date** 和 **end_date**：记录驾驶行程的起止时间，使用UTC时区的微秒级时间戳，确保时间记录的精确性。
- **distance**：表示本次驾驶的总行驶距离，单位为公里，数据类型为浮点数。
- **speed_max**：本次驾驶过程中的最高速度，单位为km/h，数据类型为整数。
- **consumption_kWh**：虽然该字段在历史版本中存在，但根据迁移文件`20190821155748_drop_consumption_columns.exs`已被移除，当前系统不再直接存储此字段。
- **start_ideal_range_km** 和 **end_ideal_range_km**：分别表示驾驶开始和结束时的理想续航里程（基于理想电池状态计算）。
- **start_rated_range_km** 和 **end_rated_range_km**：分别表示驾驶开始和结束时的额定续航里程（基于车辆出厂标定的续航能力）。
- **outside_temp_avg** 和 **inside_temp_avg**：记录驾驶过程中的外部和内部平均温度，用于分析环境对能耗的影响。
- **duration_min**：本次驾驶的持续时间，以分钟为单位。

这些字段的设计旨在全面捕捉驾驶过程中的关键性能指标，为后续的驾驶行为分析、能耗评估和车辆性能监控提供数据支持。

**Section sources**
- [drive.ex](file://lib/teslamate/log/drive.ex#L9-L26)
- [20190913175011_add_rated_range_to_drives.exs](file://priv/repo/migrations/20190913175011_add_rated_range_to_drives.exs#L10-L13)
- [20200410112005_database_efficiency_improvements.exs](file://priv/repo/migrations/20200410112005_database_efficiency_improvements.exs#L33-L52)

## 与Cars表的外键关联
Drives表通过`car_id`字段与Cars表建立外键关联，形成一对多的关系。每辆汽车（Cars表中的一条记录）可以有多个驾驶行程（Drives表中的多条记录）。

在`drive.ex`模型文件中，通过`belongs_to :car, Car`定义了这种关联关系。同时，在数据库迁移文件`20200203120311_cascade_delete.exs`中，通过`modify(:car_id, references(:cars, on_delete: :delete_all), null: false)`设置了级联删除约束，确保当一辆汽车被删除时，其所有相关的驾驶记录也会被自动删除。

此外，`car.ex`模型文件中的`has_many :drives, Drive`定义了反向关联，使得可以从汽车记录直接访问其所有的驾驶行程。这种双向关联设计简化了数据查询和遍历操作。

**Section sources**
- [drive.ex](file://lib/teslamate/log/drive.ex#L36)
- [car.ex](file://lib/teslamate/log/car.ex#L27)
- [20200203120311_cascade_delete.exs](file://priv/repo/migrations/20200203120311_cascade_delete.exs#L51-L53)

## 与Positions表的连接方式
Drives表通过起点和终点位置ID与Positions表进行连接，以记录驾驶行程的起止位置信息。

具体来说，Drives表包含`start_position_id`和`end_position_id`两个字段，它们都是指向Positions表的外键。在`drive.ex`模型中，通过`belongs_to :start_position, Position`和`belongs_to :end_position, Position`定义了这两个关联。

当一个驾驶行程结束时，系统会从与该行程关联的位置记录（Positions）中，根据时间顺序确定第一个和最后一个位置点，并将它们的ID分别赋值给`start_position_id`和`end_position_id`。这一逻辑在`log.ex`文件的`close_drive`函数中实现，通过Ecto查询的`first_value`和`last_value`窗口函数来获取起止位置的ID。

此外，Drives表还通过`has_many :positions, Position`与Positions表建立一对多关系，表示一个驾驶行程由多个位置点组成，这为分析驾驶过程中的详细轨迹提供了基础。

**Section sources**
- [drive.ex](file://lib/teslamate/log/drive.ex#L27-L28)
- [position.ex](file://lib/teslamate/log/position.ex#L38)
- [log.ex](file://lib/teslamate/log.ex#L250-L251)
- [20191003130650_add_start_and_end_position_to_drives.exs](file://priv/repo/migrations/20191003130650_add_start_and_end_position_to_drives.exs#L6-L7)

## efficiency与consumption_kWh_100km的计算逻辑
尽管`consumption_kWh`和`consumption_kWh_100km`字段已被从Drives表中移除（见`20190821155748_drop_consumption_columns.exs`），但系统的能耗分析功能依然存在，其计算逻辑已转移到其他层面。

`efficiency`（效率）字段存储在Cars表中，表示车辆的能耗效率（单位：kWh/km）。该值并非直接测量，而是通过分析充电过程数据动态计算得出。在`log.ex`文件的`recalculate_efficiency`函数中，系统会查询`charging_processes`表，计算充电量（`charge_energy_added`）与续航里程增加量（`end_rated_range_km - start_rated_range_km`）的比值，从而推导出车辆的能耗效率。这个计算过程会根据用户设置的`preferred_range`（理想或额定续航）来选择相应的续航字段。

`consumption_kWh_100km`（每百公里耗电量）这一指标虽然不再作为表字段存储，但在Grafana仪表盘等前端展示中，会通过SQL查询实时计算。例如，在`efficiency.json`仪表盘中，通过`range_loss * c.efficiency / convert_km(distance::numeric, '$length_unit') * 1000`这样的公式，结合已知的效率值和行驶距离来计算净能耗。

这种将计算逻辑后移的设计，避免了数据冗余，提高了数据的一致性和灵活性。

**Section sources**
- [car.ex](file://lib/teslamate/log/car.ex#L10)
- [log.ex](file://lib/teslamate/log.ex#L635-L674)
- [20190821155748_drop_consumption_columns.exs](file://priv/repo/migrations/20190821155748_drop_consumption_columns.exs#L6-L7)
- [efficiency.json](file://grafana/dashboards/efficiency.json#L255)

## 驾驶行程的开始与结束判定机制
驾驶行程的开始与结束判定是通过车辆状态监控和日志记录逻辑实现的。

系统通过Tesla的API流式数据或定期轮询来监控车辆状态。当检测到车辆从“停车”（P档）状态切换到“行驶”（D或R档）状态，并且车速大于0时，系统会触发`start_drive`事件，创建一个新的Drives记录，并将当前时间作为`start_date`。这一逻辑在`vehicles/vehicle/driving.ex`等模块中实现。

驾驶行程的结束判定则更为复杂。当车辆停止行驶（速度为0）并长时间保持静止时，系统会启动一个计时器。如果车辆在设定的静止时间（由`suspend_after_idle_min`等设置控制）内没有再次移动，系统会认为本次驾驶已经结束，触发`close_drive`函数。该函数会执行一系列操作：
1.  查询与该行程关联的所有位置点（Positions）。
2.  计算并填充`distance`、`duration_min`、`speed_max`、`outside_temp_avg`等聚合字段。
3.  确定起止位置ID，并尝试关联起止地址和地理围栏。
4.  更新Drives记录的`end_date`和其他字段。

如果在计时期间车辆再次移动，则计时器重置，驾驶行程继续。这种机制确保了驾驶行程的准确划分，避免了因短暂停车而错误地分割一次完整的驾驶。

**Section sources**
- [log.ex](file://lib/teslamate/log.ex#L243-L374)
- [vehicle.ex](file://lib/teslamate/vehicles/vehicle.ex)
- [suspend_logging_test.exs](file://test/teslamate/vehicles/vehicle/suspend_logging_test.exs)
- [driving_test.exs](file://test/teslamate/vehicles/vehicle/driving_test.exs)