# Home Assistant配置

<cite>
**本文档中引用的文件**   
- [home_assistant.md](file://website/docs/integrations/home_assistant.md)
- [mqtt.md](file://website/docs/integrations/mqtt.md)
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex)
- [publisher.ex](file://lib/teslamate/mqtt/publisher.ex)
- [runtime.exs](file://config/runtime.exs)
</cite>

## 目录
1. [简介](#简介)
2. [configuration.yaml配置](#configurationyaml配置)
3. [mqtt_sensors.yaml配置](#mqtt_sensorsyaml配置)
4. [proximity传感器配置与应用](#proximity传感器配置与应用)
5. [设备追踪与位置信息](#设备追踪与位置信息)
6. [自动化场景示例](#自动化场景示例)
7. [MQTT实体ID命名规范](#mqtt实体id命名规范)
8. [配置调试与常见问题](#配置调试与常见问题)

## 简介

TeslaMate是一个开源的特斯拉车辆数据记录和分析工具，它通过MQTT协议与Home Assistant集成，提供了丰富的车辆状态信息。与官方的Tesla组件相比，TeslaMate的轮询机制更加高效，不会导致车辆持续唤醒而耗电。本文档详细介绍了如何配置TeslaMate与Home Assistant的集成，重点包括`configuration.yaml`和`mqtt_sensors.yaml`的配置方法，以及proximity传感器在自动化场景中的应用。

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#introduction)

## configuration.yaml配置

`configuration.yaml`是Home Assistant的主要配置文件，用于定义系统的基本设置和集成。在TeslaMate集成中，需要在该文件中配置proximity传感器、Tesla组件和MQTT集成。

```yml
automation: !include automation.yaml

proximity:
  home_tesla:
    zone: home
    devices:
      - device_tracker.tesla_location
    tolerance: 10
    unit_of_measurement: km

tesla:
  username: !secret tesla_username
  password: !secret tesla_password
  scan_interval: 3600

mqtt: !include mqtt_sensors.yaml
```

上述配置中，`proximity`部分定义了proximity传感器，用于计算车辆到指定区域的距离。`tesla`部分配置了官方Tesla组件，但设置了较长的轮询间隔以减少对车辆的影响。`mqtt`部分引用了`mqtt_sensors.yaml`文件，用于定义从TeslaMate接收的MQTT传感器。

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#configuration)

## mqtt_sensors.yaml配置

`mqtt_sensors.yaml`文件定义了从TeslaMate通过MQTT接收到的所有传感器、二进制传感器和设备追踪器。这些配置允许Home Assistant显示车辆的各种状态信息。

```yml
- sensor:
    name: Display Name
    default_entity_id: sensor.tesla_display_name
    unique_id: teslamate_1_display_name
    device: &teslamate_device_info
      identifiers: [teslamate_car_1]
      configuration_url: <teslamate url>
      manufacturer: Tesla
      model: <your tesla model>
      name: <your tesla name>
    state_topic: "teslamate/cars/1/display_name"
    icon: mdi:car

- device_tracker:
    name: Location
    default_entity_id: device_tracker.tesla_location
    unique_id: teslamate_1_location
    device: *teslamate_device_info
    json_attributes_topic: "teslamate/cars/1/location"
    icon: mdi:crosshairs-gps

- binary_sensor:
    name: Healthy
    default_entity_id: binary_sensor.tesla_healthy
    unique_id: teslamate_1_healthy
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/healthy"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:heart-pulse
```

该配置文件包含了所有可用的车辆状态传感器，如电池电量、充电状态、车辆位置等。每个传感器都定义了名称、实体ID、唯一ID、设备信息、状态主题和图标。设备信息使用YAML锚点`&teslamate_device_info`定义，并在其他传感器中通过`*teslamate_device_info`引用，以避免重复配置。

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#mqtt_sensorsyaml-mqtt-configurationyaml)

## proximity传感器配置与应用

proximity传感器是Home Assistant中用于计算设备到指定区域距离的工具。在TeslaMate集成中，proximity传感器可以用于实现自动车库门开启、车辆到达通知等自动化场景。

### 配置方法

proximity传感器的配置在`configuration.yaml`文件中完成，主要参数包括：

- `zone`: 目标区域，通常为`home`
- `devices`: 要追踪的设备，如`device_tracker.tesla_location`
- `tolerance`: 容差，单位为`unit_of_measurement`，用于定义距离变化的最小阈值
- `unit_of_measurement`: 距离单位，可选`km`或`m`

### 自动化应用

proximity传感器可以用于以下自动化场景：

- **自动车库门开启**: 当车辆进入家附近一定距离时，自动开启车库门
- **车辆到达通知**: 当车辆接近家时，发送通知提醒
- **节能模式**: 当车辆离开家一定距离时，自动关闭家中非必要设备

这些自动化可以通过Home Assistant的自动化编辑器或YAML配置实现，利用proximity传感器的状态变化作为触发条件。

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#configuration)

## 设备追踪与位置信息

TeslaMate通过MQTT提供车辆的实时位置信息，这些信息可以通过`device_tracker`和`json_attributes_topic`获取。

### device_tracker配置

`device_tracker`用于追踪车辆的位置，配置如下：

```yml
- device_tracker:
    name: Location
    default_entity_id: device_tracker.tesla_location
    unique_id: teslamate_1_location
    device: *teslamate_device_info
    json_attributes_topic: "teslamate/cars/1/location"
    icon: mdi:crosshairs-gps
```

### json_attributes_topic

`json_attributes_topic`用于获取车辆位置的详细信息，包括经纬度。该主题发布的内容为JSON格式，包含`latitude`和`longitude`字段。通过配置`json_attributes_topic`，可以在Home Assistant中显示车辆的精确位置，并在地图卡片中使用。

此外，`active_route`主题提供了车辆的活动路线信息，包括目的地、预计到达时间、剩余里程等。这些信息可以通过`json_attributes_topic`和`json_attributes_template`提取并显示。

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#mqtt_sensorsyaml-mqtt-configurationyaml)
- [mqtt.md](file://website/docs/integrations/mqtt.md#mqtt-topics)

## 自动化场景示例

以下是一些基于TeslaMate MQTT数据的实用自动化示例。

### 车库门自动化

当车辆返回家时，自动开启车库门：

```yml
- alias: Open garage if car returns home
  initial_state: on
  trigger:
    - platform: state
      entity_id: device_tracker.tesla_location
      from: "not_home"
      to: "home"
  action:
    - service: switch.turn_on
      entity_id: switch.garage_door_switch
```

### 车门车窗未关闭通知

当检测到车门或车窗未关闭时，延迟5分钟后发送通知：

```yml
- alias: Set timer if teslamate reports something is open to alert us
  initial_state: on
  trigger:
    - platform: mqtt
      topic: teslamate/cars/1/windows_open
      payload: "true"
    - platform: mqtt
      topic: teslamate/cars/1/doors_open
      payload: "true"
  action:
    - service: script.turn_on
      data_template:
        entity_id: script.notify_tesla_{{trigger.topic.split('/')[3]}}

- alias: Cancel notification if said door/window is closed
  initial_state: on
  trigger:
    - platform: mqtt
      topic: teslamate/cars/1/windows_open
      payload: "false"
    - platform: mqtt
      topic: teslamate/cars/1/doors_open
      payload: "false"
  action:
    - service: script.turn_off
      data_template:
        entity_id: script.notify_tesla_{{trigger.topic.split('/')[3]}}
```

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#useful-automations)

## MQTT实体ID命名规范

TeslaMate的MQTT实体ID遵循以下命名规范：

- **主题前缀**: `teslamate/cars/$car_id/`，其中`$car_id`通常从1开始
- **设备分类**: 传感器、二进制传感器和设备追踪器通过不同的配置类型区分
- **单位设置**: 在传感器配置中通过`unit_of_measurement`指定，如`km/h`、`%`、`kW`等
- **图标选择**: 使用Material Design Icons（mdi）图标，如`mdi:car`、`mdi:battery-80`等

设备信息中的`identifiers`字段使用`teslamate_car_$car_id`格式，确保每个车辆的设备在Home Assistant中正确分组。

**Section sources**
- [mqtt.md](file://website/docs/integrations/mqtt.md#mqtt-topics)
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex#L202-L205)

## 配置调试与常见问题

### 调试技巧

- **检查MQTT连接**: 确保TeslaMate和Home Assistant都能连接到MQTT broker
- **查看日志**: 检查Home Assistant和TeslaMate的日志，查找错误信息
- **测试MQTT主题**: 使用MQTT客户端（如MQTT Explorer）订阅相关主题，验证数据是否正常发布

### 常见问题

- **传感器不更新**: 检查MQTT连接和TeslaMate的轮询状态
- **位置信息不准确**: 确保`json_attributes_topic`配置正确，并检查GPS信号
- **自动化不触发**: 验证触发条件和实体ID是否正确

通过以上配置和调试方法，可以确保TeslaMate与Home Assistant的集成稳定可靠，充分发挥车辆数据的价值。

**Section sources**
- [home_assistant.md](file://website/docs/integrations/home_assistant.md#useful-automations)
- [runtime.exs](file://config/runtime.exs#L168-L178)