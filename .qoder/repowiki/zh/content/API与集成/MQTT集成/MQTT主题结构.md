# MQTT主题结构

<cite>
**本文档中引用的文件**   
- [mqtt.ex](file://lib/teslamate/mqtt.ex)
- [publisher.ex](file://lib/teslamate/mqtt/publisher.ex)
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex)
- [summary.ex](file://lib/teslamate/vehicles/vehicle/summary.ex)
- [mqtt.md](file://website/docs/integrations/mqtt.md)
- [environment_variables.md](file://website/docs/configuration/environment_variables.md)
</cite>

## 目录
1. [MQTT主题层级结构](#mqtt主题层级结构)
2. [车辆ID与多车数据流区分](#车辆id与多车数据流区分)
3. [可用主题与数据类型](#可用主题与数据类型)
4. [已弃用主题与迁移路径](#已弃用主题与迁移路径)
5. [动态主题生成机制](#动态主题生成机制)
6. [Publisher模块实现](#publisher模块实现)
7. [实际使用示例](#实际使用示例)

## MQTT主题层级结构

TeslaMate的MQTT主题采用分层结构，以`teslamate`为根前缀，其下分为`cars`和`$car_id`层级，用于组织车辆数据。主题结构遵循`teslamate/cars/$car_id/`的格式，其中`$car_id`代表车辆的唯一标识符。该结构允许用户通过订阅特定车辆ID的主题来获取对应车辆的数据。

主题层级设计支持命名空间（namespace）配置，通过`MQTT_NAMESPACE`环境变量可插入自定义命名空间，例如设置`MQTT_NAMESPACE=account_0`时，主题将变为`teslamate/account_0/cars/$car_id/state`。这种设计增强了多账户或多实例部署的灵活性。

**Section sources**
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex#L202-L206)
- [environment_variables.md](file://website/docs/configuration/environment_variables.md#L37)

## 车辆ID与多车数据流区分

TeslaMate通过车辆ID（car_id）区分多辆车的数据流。每辆车在系统中被分配一个唯一的ID，通常从1开始递增。当系统中有多个车辆时，每个车辆的数据发布到以其ID命名的独立主题下，确保数据流的隔离性和可识别性。

在代码实现中，`VehicleSubscriber`模块为每辆车创建独立的订阅者进程，通过`car_id`参数区分不同车辆。当车辆状态更新时，系统根据`car_id`生成对应的主题路径，并将数据发布到该主题。这种设计使得用户可以针对特定车辆进行订阅和监控，而不会受到其他车辆数据的干扰。

**Section sources**
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex#L43)
- [mqtt.md](file://website/docs/integrations/mqtt.md#L91)

## 可用主题与数据类型

TeslaMate提供了丰富的MQTT主题，涵盖车辆状态、位置信息、充电数据、气候控制、车门状态等多个方面。以下是主要主题及其对应的数据类型：

| 主题 | 数据类型 | 描述 |
| --- | --- | --- |
| `teslamate/cars/$car_id/display_name` | 字符串 | 车辆名称 |
| `teslamate/cars/$car_id/state` | 字符串 | 车辆状态（如`online`、`asleep`、`charging`） |
| `teslamate/cars/$car_id/battery_level` | 数字 | 电池电量百分比 |
| `teslamate/cars/$car_id/location` | JSON对象 | 车辆位置（包含latitude和longitude） |
| `teslamate/cars/$car_id/charging_state` | 字符串 | 充电状态（Charging、Disconnected等） |
| `teslamate/cars/$car_id/is_climate_on` | 布尔值 | 气候控制是否开启 |
| `teslamate/cars/$car_id/locked` | 布尔值 | 车辆是否锁定 |
| `teslamate/cars/$car_id/speed` | 数字 | 当前速度（km/h） |
| `teslamate/cars/$car_id/odometer` | 数字 | 里程表读数（km） |
| `teslamate/cars/$car_id/geofence` | 字符串 | 当前地理位置围栏名称 |

**Section sources**
- [summary.ex](file://lib/teslamate/vehicles/vehicle/summary.ex#L8-22)
- [mqtt.md](file://website/docs/integrations/mqtt.md#L14-L88)

## 已弃用主题与迁移路径

TeslaMate在版本演进过程中对部分主题进行了更新和弃用。最显著的变化是位置信息主题的迁移：旧的`latitude`和`longitude`主题已被弃用，取而代之的是新的`location`主题。`location`主题以JSON格式发布位置数据，包含latitude和longitude字段，提供了更结构化的数据表示。

迁移路径建议：用户应停止订阅`teslamate/cars/$car_id/latitude`和`teslamate/cars/$car_id/longitude`主题，转而订阅`teslamate/cars/$car_id/location`主题。新主题不仅提供了相同的位置信息，还通过JSON格式增强了数据的可解析性和扩展性。此外，`active_route_destination`、`active_route_latitude`和`active_route_longitude`主题也已被标记为弃用，推荐使用`active_route`主题获取导航信息。

**Section sources**
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex#L121-L143)
- [mqtt.md](file://website/docs/integrations/mqtt.md#L30-L32)

## 动态主题生成机制

TeslaMate的MQTT主题生成机制是动态的，基于车辆状态和配置实时生成。主题生成的核心逻辑位于`VehicleSubscriber`模块的`publish`函数中，该函数接收车辆状态更新并生成相应的主题路径。

主题生成过程遵循以下步骤：首先，将基础路径`teslamate`、命名空间、`cars`、`car_id`和具体属性名组合成一个列表；然后，过滤掉列表中的空值；最后，使用斜杠连接各部分形成最终的主题字符串。这种动态生成机制确保了主题结构的灵活性和可扩展性，同时通过`Enum.reject(&is_nil(&1))`过滤空值保证了主题路径的合法性。

**Section sources**
- [vehicle_subscriber.ex](file://lib/teslamate/mqtt/pubsub/vehicle_subscriber.ex#L202-L206)
- [publisher.ex](file://lib/teslamate/mqtt/publisher.ex#L21)

## Publisher模块实现

MQTT发布功能由`Publisher`模块实现，该模块基于GenServer行为构建。`Publisher`模块提供了`publish/3`函数作为外部接口，接收主题、消息和选项参数。内部通过`GenServer.call`机制处理发布请求，确保线程安全和状态管理。

发布逻辑根据QoS（服务质量）级别进行区分：当QoS为0时，直接调用`Tortoise311.publish`发送消息；当QoS大于0时，先获取发布引用，再异步发送消息，并通过`handle_info`回调处理发布结果。这种设计平衡了性能和可靠性，既支持快速发布，又确保了重要消息的可靠传递。

**Section sources**
- [publisher.ex](file://lib/teslamate/mqtt/publisher.ex#L20-L52)
- [mqtt.ex](file://lib/teslamate/mqtt.ex#L18)

## 实际使用示例

要订阅TeslaMate的MQTT主题，首先需要配置MQTT客户端连接到指定的MQTT代理。以下是一个使用Python的paho-mqtt库订阅车辆状态的示例：

```python
import paho.mqtt.client as mqtt
import json

def on_connect(client, userdata, flags, rc):
    print("Connected with result code "+str(rc))
    client.subscribe("teslamate/cars/1/state")
    client.subscribe("teslamate/cars/1/location")

def on_message(client, userdata, msg):
    if msg.topic == "teslamate/cars/1/location":
        location = json.loads(msg.payload)
        print(f"车辆位置: 纬度 {location['latitude']}, 经度 {location['longitude']}")
    else:
        print(f"{msg.topic}: {msg.payload.decode()}")

client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

client.connect("localhost", 1883, 60)
client.loop_forever()
```

此示例展示了如何连接到MQTT代理，订阅车辆状态和位置主题，并解析接收到的消息。对于JSON格式的主题如`location`，需要使用`json.loads`解析消息内容。

**Section sources**
- [mqtt.md](file://website/docs/integrations/mqtt.md#L96-L119)
- [publisher.ex](file://lib/teslamate/mqtt/publisher.ex#L37-L42)