# TeslaMate SaaS 架构改造设计方案

## 设计目标

将 TeslaMate 从单租户数据采集系统改造为支持多租户的数据采集层，配合 Go + Gin 框架的业务 API 层构建完整的 SaaS 平台。改造遵循"最少量修改"原则，确保每一步改造后系统可运行、可测试。

## 架构愿景

### 系统分层架构

| 层级 | 技术栈 | 职责范围 |
|------|--------|---------|
| **业务 API 层** | Go + Gin | 用户管理、租户系统、业务 API、权限控制、数据聚合 |
| **数据采集层** | TeslaMate (Elixir) | Tesla API 集成、车辆数据采集、原始数据存储 |
| **数据存储层** | PostgreSQL | 多租户数据隔离、数据持久化 |

### 租户隔离策略

采用**共享数据库 + 租户标识列**模式：
- 所有租户共享同一个 PostgreSQL 数据库实例
- 核心表增加 `tenant_id` 字段实现数据隔离
- 通过数据库级约束和应用层过滤保证隔离安全性

### 改造边界

**TeslaMate 保留职责：**
- Tesla API 认证与通信
- 车辆数据实时采集
- 原始数据持久化
- 基础监督树与容错机制

**TeslaMate 移除功能：**
- Web 管理界面（TeslaMateWeb.Endpoint）
- MQTT 消息发布
- Grafana 仪表板支持
- Updater 版本检查
- Terrain 地形服务（可选）
- Repair 数据修复服务（可选）

**Go + Gin 新增职责：**
- 租户注册与管理
- 用户认证与授权
- Tesla 账户绑定管理
- 车辆列表与状态查询
- 数据聚合与统计 API
- 前端界面服务

## 改造阶段规划

### 阶段一：精简 TeslaMate 项目

**目标：** 移除非必要组件，降低资源消耗，保留核心数据采集能力

#### 1.1 移除 Web 界面

**修改文件：** `lib/teslamate/application.ex`

**变更说明：**
在 `children/0` 函数中移除 `TeslaMateWeb.Endpoint` 启动项，该组件包含：
- Phoenix LiveView WebSocket 连接
- 静态资源服务
- Session 管理
- HTTP 路由处理

**影响评估：**
- 不再提供 Web 管理界面访问
- 释放端口 4000 占用
- 减少内存占用约 50-100MB

**环境变量调整：**
无需配置 `PORT`、`VIRTUAL_HOST`、`CHECK_ORIGIN` 等 Web 相关变量

#### 1.2 禁用 MQTT 功能

**修改文件：** `lib/teslamate/application.ex`

**变更说明：**
移除 `TeslaMate.Mqtt` 及 `TeslaMate.Mqtt.PubSub` 启动项，该模块包含：
- Tortoise311 MQTT 客户端连接
- 车辆状态消息发布
- MQTT 订阅管理

**影响评估：**
- 不再向外部 MQTT 代理发布消息
- 无法与 Home Assistant 等系统集成
- 减少网络连接和 CPU 开销

**环境变量调整：**
可移除 `MQTT_HOST`、`MQTT_PORT`、`MQTT_USERNAME`、`MQTT_PASSWORD` 等配置，或直接设置 `DISABLE_MQTT=true`

#### 1.3 移除版本更新检查器

**修改文件：** `lib/teslamate/application.ex`

**变更说明：**
移除 `TeslaMate.Updater` 启动项，该模块功能：
- 定期查询 GitHub Releases API
- 比对当前版本与最新版本
- 在 Web 界面显示更新提示

**影响评估：**
- 不再进行版本检查
- 减少对 GitHub API 的网络请求
- 简化启动依赖

#### 1.4 禁用地形服务（可选）

**修改文件：** `lib/teslamate/application.ex`

**变更说明：**
将 `TeslaMate.Terrain` 启动参数设置为 `disabled: true`，该服务功能：
- 根据经纬度查询海拔高度
- 使用 SRTM 数据集
- 定期更新缺失海拔的位置记录

**影响评估：**
- 位置记录的 `elevation` 字段将为空
- 减少磁盘 I/O 和外部 API 调用
- 如业务需要高程数据，可保留此服务

**配置方式：**
在启动参数中添加 `{TeslaMate.Terrain, disabled: true}`

#### 1.5 移除数据修复服务（可选）

**修改文件：** `lib/teslamate/application.ex`

**变更说明：**
移除 `TeslaMate.Repair` 启动项，该服务功能：
- 定期扫描缺失地址关联的行程和充电记录
- 调用地理编码 API 补全地址信息
- 使用熔断器防止 API 过载

**影响评估：**
- 历史数据的地址关联可能不完整
- 减少对 OpenStreetMap Nominatim API 的调用
- 如需数据完整性，可通过 Go 层异步任务实现

#### 1.6 精简后的监督树结构

**最终 children 列表：**

| 组件 | 职责 | 保留原因 |
|------|------|---------|
| TeslaMate.Repo | 数据库连接池 | 核心数据持久化 |
| TeslaMate.Vault | 加密密钥管理 | Token 加密存储 |
| TeslaMate.HTTP | Finch HTTP 客户端 | Tesla API 通信 |
| TeslaMate.Api | Tesla API 管理器 | Token 刷新与 API 调用 |
| Phoenix.PubSub | 进程间消息总线 | 内部事件通知 |
| TeslaMate.Vehicles | 车辆监督器 | 核心数据采集逻辑 |

**验证方式：**
- 启动应用后检查 Supervisor 树结构
- 确认车辆进程正常启动
- 观察数据库中数据记录是否持续写入

### 阶段二：OAuth 认证改造

**目标：** 替换原有单一 Token 存储，支持多租户 Tesla 账户管理

#### 2.1 数据库模式变更

**现有表结构：** `private.tokens`

| 字段 | 类型 | 说明 |
|------|------|------|
| id | integer | 主键 |
| access | bytea (encrypted) | 访问令牌 |
| refresh | bytea (encrypted) | 刷新令牌 |
| inserted_at | timestamp | 创建时间 |
| updated_at | timestamp | 更新时间 |

**新表结构：** 由 Go + GORM 管理的 `tesla_accounts`

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | uuid | PRIMARY KEY | 主键 |
| created_at | timestamp | NOT NULL | 创建时间 |
| updated_at | timestamp | NOT NULL | 更新时间 |
| deleted_at | timestamp | - | 软删除时间 |
| tenant_id | uuid | NOT NULL, INDEX | 租户外键 |
| encrypted_access_token | text | NOT NULL | 加密访问令牌 |
| encrypted_refresh_token | text | NOT NULL | 加密刷新令牌 |
| token_expiry | timestamp | NOT NULL | 令牌过期时间 |
| tesla_account_email | varchar(255) | NOT NULL, INDEX | Tesla 账户邮箱 |

**索引设计：**
- `idx_tesla_accounts_tenant_id`: 租户查询加速
- `idx_tesla_accounts_email`: 邮箱唯一性校验
- `idx_tesla_accounts_deleted_at`: 软删除过滤

**迁移策略：**
1. 由 Go 应用执行 GORM AutoMigrate 创建新表
2. 手动迁移现有 `private.tokens` 数据到新表（如需）
3. 废弃 `private.tokens` 表（保留备份）

#### 2.2 Elixir 模式适配

**移除文件：** `lib/teslamate/auth/tokens.ex`

**新建文件：** `lib/teslamate/auth/tesla_account.ex`

**Ecto Schema 定义：**

核心字段映射：
- `tenant_id`: UUID 类型，关联租户
- `encrypted_access_token`: 映射到 Vault.Encrypted.Binary
- `encrypted_refresh_token`: 映射到 Vault.Encrypted.Binary  
- `token_expiry`: 时间戳类型
- `tesla_account_email`: 字符串类型

Schema 配置：
- `@schema_prefix`: 使用 `public` 模式（或根据需要配置）
- `@primary_key`: 使用 UUID 类型
- `@timestamps_opts`: 配置时间戳字段名称

**Changeset 验证规则：**
- 必填字段：`tenant_id`, `encrypted_access_token`, `encrypted_refresh_token`, `token_expiry`, `tesla_account_email`
- 格式验证：`tesla_account_email` 邮箱格式
- 唯一性约束：同一租户下邮箱唯一

#### 2.3 TeslaMate.Api 模块改造

**修改文件：** `lib/teslamate/api.ex`

**核心变更点：**

**初始化流程调整：**
- `init/1` 函数接收 `tenant_id` 参数
- 从数据库查询该租户的 Tesla 账户记录
- 如果存在有效 Token，自动刷新并启动车辆监控

**Token 查询逻辑：**
- 根据 `tenant_id` 查询 `tesla_accounts` 表
- 检查 `token_expiry` 判断是否需要刷新
- 使用 Vault 解密 Token

**Token 保存逻辑：**
- `sign_in` 成功后创建或更新 `tesla_accounts` 记录
- 存储 `tenant_id` 关联
- 加密 Token 后写入数据库

**状态管理变更：**
- State 结构体增加 `tenant_id` 字段
- ETS 表 key 从 `:auth` 改为 `{:auth, tenant_id}`
- 支持同时管理多个租户的认证状态

**API 函数签名调整：**
- `list_vehicles(name, tenant_id)`
- `get_vehicle_with_state(name, tenant_id, vehicle_id)`
- `sign_in(name, tenant_id, credentials)`

#### 2.4 认证流程时序

**租户首次绑定 Tesla 账户：**

1. 用户在 Go 前端输入 Tesla 账户凭证
2. Go 服务调用 TeslaMate GenServer: `Api.sign_in(tenant_id, credentials)`
3. TeslaMate 调用 Tesla OAuth2 端点获取 Token
4. TeslaMate 创建 `tesla_accounts` 记录，关联 `tenant_id`
5. TeslaMate 调度自动刷新任务
6. 返回成功响应给 Go 层

**Token 自动刷新流程：**

1. TeslaMate.Api 定时器触发 `:refresh_auth` 消息
2. 根据 `tenant_id` 查询数据库获取 refresh_token
3. 调用 `TeslaApi.Auth.Refresh.refresh/1`
4. 更新 `tesla_accounts` 表中的 Token 和过期时间
5. 重置 ETS 缓存
6. 调度下次刷新（75% 过期时间）

**多租户并发处理：**

- 每个租户的 Token 独立管理
- 使用 ETS 表缓存避免频繁数据库查询
- 熔断器按租户隔离，防止单个租户故障影响全局

### 阶段三：租户监督树改造

**目标：** 引入租户级监督器，实现租户隔离的车辆管理

#### 3.1 新增租户监督器

**新建文件：** `lib/teslamate/tenants.ex`

**职责定义：**

监督器管理：
- 为每个活跃租户启动独立的监督器实例
- 监督器命名规则：`TeslaMate.Tenant.{tenant_id}`
- 采用 `:one_for_one` 策略确保租户隔离

子进程管理：
- 每个租户监督器下启动该租户的 `Vehicles` 监督器
- 租户级别的 `Api` GenServer 实例
- 可选的租户级别缓存或状态管理器

生命周期控制：
- `start_tenant(tenant_id)`: 启动租户监督树
- `stop_tenant(tenant_id)`: 停止租户监督树
- `restart_tenant(tenant_id)`: 重启租户监督树
- `list_tenants()`: 查询所有活跃租户

**监督树层级：**

```
TeslaMate.Supervisor (应用顶级)
├── TeslaMate.Repo
├── TeslaMate.Vault  
├── TeslaMate.HTTP
├── Phoenix.PubSub
└── TeslaMate.Tenants (新增租户监督器)
    ├── TeslaMate.Tenant.{tenant_id_1}
    │   ├── TeslaMate.Api (租户级)
    │   └── TeslaMate.Vehicles (租户级)
    │       ├── Vehicle (车辆 1)
    │       ├── Vehicle (车辆 2)
    │       └── ...
    ├── TeslaMate.Tenant.{tenant_id_2}
    │   ├── TeslaMate.Api (租户级)
    │   └── TeslaMate.Vehicles (租户级)
    └── ...
```

#### 3.2 租户监督器实现细节

**init/1 回调：**

租户发现机制：
- 从数据库查询所有包含有效 Tesla 账户的租户
- 查询条件：`token_expiry > now() AND deleted_at IS NULL`
- 或从 Go 服务接收租户列表（通过 API 或共享状态）

子进程规格生成：
- 为每个租户生成 `{TeslaMate.Tenant.Supervisor, tenant_id: tenant_id}` 规格
- 使用动态命名避免进程冲突
- 配置独立的重启策略

**动态租户管理：**

添加租户：
- 接收 Go 服务的通知或定期轮询数据库
- 调用 `Supervisor.start_child/2` 启动新租户监督树
- 验证租户是否已存在，避免重复启动

移除租户：
- 接收租户删除通知
- 调用 `Supervisor.terminate_child/2` 和 `Supervisor.delete_child/2`
- 确保优雅关闭所有子进程

#### 3.3 租户级 Vehicles 监督器改造

**修改文件：** `lib/teslamate/vehicles.ex`

**参数传递：**

启动配置：
- `start_link/1` 接收 `tenant_id` 选项
- 监督器命名：`:"Vehicles_#{tenant_id}"`
- 避免全局命名冲突

**车辆查询逻辑：**

数据源调整：
- `list_vehicles!/0` 改为 `list_vehicles!(tenant_id)`
- 调用 `TeslaMate.Api.list_vehicles(api_name, tenant_id)`
- 回退逻辑查询 `Log.list_cars(tenant_id)`

**车辆创建逻辑：**

租户关联：
- `create_or_update!/2` 接收 `tenant_id` 参数
- 创建 `Car` 记录时设置 `tenant_id` 字段
- 确保车辆与租户的绑定关系

#### 3.4 数据库模式扩展

**核心表增加租户字段：**

**cars 表：**
- 增加 `tenant_id uuid NOT NULL`
- 创建索引 `idx_cars_tenant_id`
- 外键约束关联租户表（由 Go 管理）

**drives 表：**
- 增加 `tenant_id uuid NOT NULL`
- 通过 `car_id` 关联获取租户信息
- 冗余字段便于查询和分区

**charging_processes 表：**
- 增加 `tenant_id uuid NOT NULL`
- 同样冗余租户信息

**positions 表：**
- 增加 `tenant_id uuid NOT NULL`
- 索引优化查询性能

**states 表：**
- 增加 `tenant_id uuid NOT NULL`
- 确保状态数据隔离

**迁移脚本示例：**

迁移任务：
1. 为所有表添加 `tenant_id` 列（允许 NULL）
2. 为现有数据填充默认租户 ID（如果有历史数据）
3. 将 `tenant_id` 设置为 NOT NULL
4. 创建索引和外键约束

Ecto Migration 结构：
- `alter table(:cars)`: 添加 `tenant_id` 字段
- `create index`: 创建租户索引
- `execute`: 执行数据填充 SQL

#### 3.5 租户隔离验证

**查询过滤：**

所有 Ecto 查询添加租户过滤：
- `from(c in Car, where: c.tenant_id == ^tenant_id)`
- 创建通用查询宏简化代码

**进程隔离：**

租户进程独立性测试：
- 一个租户的车辆进程崩溃不影响其他租户
- 租户级监督器重启不影响全局服务
- 内存和资源按租户隔离统计

**性能测试：**

多租户并发场景：
- 模拟 10 个租户同时采集数据
- 验证数据库连接池管理
- 监控 CPU 和内存使用

### 阶段四：Go + Gin 业务层集成

**目标：** 构建完整的 SaaS API 层，实现用户管理、租户系统和数据聚合

#### 4.1 Go 服务职责边界

**用户与租户管理：**
- 用户注册与登录（JWT 认证）
- 租户创建与管理
- 用户与租户关联（多租户 RBAC）
- Tesla 账户绑定流程

**TeslaMate 集成接口：**
- 通过 GenServer 调用 TeslaMate 功能（可选 Port 或 HTTP）
- 或通过共享 PostgreSQL 数据库直接查询
- 租户激活时通知 TeslaMate 启动车辆监控
- 租户停用时通知 TeslaMate 停止监控

**数据查询与聚合：**
- 车辆列表与实时状态查询
- 行程历史与统计分析
- 充电记录与成本计算
- 数据导出与报表生成

**前端服务：**
- RESTful API 或 GraphQL
- WebSocket 实时数据推送
- 前端静态资源服务

#### 4.2 数据库交互模式

**方案一：共享数据库直接查询**

Go 侧数据模型：
- 使用 GORM 定义与 TeslaMate 相同的表结构
- 添加 `tenant_id` 过滤条件
- 只读查询，避免数据一致性问题

优点：
- 实现简单，无需跨进程通信
- 查询性能高

缺点：
- 数据模型重复定义
- 需要维护 Schema 一致性

**方案二：通过 GenServer RPC 调用**

Elixir 侧暴露接口：
- 创建 `TeslaMate.Api.External` 模块
- 提供 `get_vehicles(tenant_id)` 等函数
- 通过 Port 或 Erlang Distribution 通信

Go 侧客户端：
- 使用 `goerlang` 或类似库建立连接
- 封装 RPC 调用为 Go 接口

优点：
- 数据封装性好
- 逻辑单一入口

缺点：
- 性能开销较大
- 增加系统复杂度

**推荐方案：** 共享数据库模式，TeslaMate 负责写入，Go 负责读取和聚合

#### 4.3 租户生命周期管理

**租户创建流程：**

1. 用户在 Go 前端创建租户
2. Go 创建 `tenants` 表记录
3. Go 返回创建成功

**Tesla 账户绑定流程：**

1. 用户输入 Tesla 账户凭证
2. Go 调用 TeslaMate: `Api.sign_in(tenant_id, credentials)`
3. TeslaMate 验证凭证并保存 Token
4. Go 通知 Tenants 监督器: `Tenants.start_tenant(tenant_id)`
5. TeslaMate 启动该租户的车辆监控进程
6. Go 返回绑定成功

**租户停用流程：**

1. 管理员在 Go 后台停用租户
2. Go 软删除 `tenants` 记录（`deleted_at` 设置时间戳）
3. Go 通知 TeslaMate: `Tenants.stop_tenant(tenant_id)`
4. TeslaMate 停止该租户的所有车辆监控
5. 保留历史数据，标记为已删除

**租户重新激活：**

1. 管理员恢复租户（清除 `deleted_at`）
2. Go 通知 TeslaMate: `Tenants.start_tenant(tenant_id)`
3. TeslaMate 检查 Token 有效性并重启监控

#### 4.4 API 设计示例

**用户认证 API：**

| 端点 | 方法 | 说明 |
|------|------|------|
| /api/auth/register | POST | 用户注册 |
| /api/auth/login | POST | 用户登录（返回 JWT） |
| /api/auth/logout | POST | 用户登出 |

**租户管理 API：**

| 端点 | 方法 | 说明 |
|------|------|------|
| /api/tenants | POST | 创建租户 |
| /api/tenants/:id | GET | 获取租户详情 |
| /api/tenants/:id | PUT | 更新租户信息 |
| /api/tenants/:id | DELETE | 停用租户 |

**Tesla 账户管理 API：**

| 端点 | 方法 | 说明 |
|------|------|------|
| /api/tenants/:id/tesla-accounts | POST | 绑定 Tesla 账户 |
| /api/tenants/:id/tesla-accounts | GET | 查询已绑定账户 |
| /api/tenants/:id/tesla-accounts/:email | DELETE | 解绑账户 |

**车辆数据 API：**

| 端点 | 方法 | 说明 |
|------|------|------|
| /api/vehicles | GET | 查询车辆列表 |
| /api/vehicles/:id | GET | 获取车辆详情 |
| /api/vehicles/:id/drives | GET | 查询行程记录 |
| /api/vehicles/:id/charges | GET | 查询充电记录 |
| /api/vehicles/:id/statistics | GET | 统计数据 |

**数据过滤与权限：**
- 所有 API 通过 JWT 识别用户
- 根据用户所属租户过滤数据
- RBAC 控制操作权限（管理员、普通用户等）

### 阶段五：后续优化与扩展

#### 5.1 性能优化

**数据库连接池：**
- TeslaMate 与 Go 独立连接池
- 根据租户数量动态调整池大小
- 监控连接使用率

**查询优化：**
- 为租户相关查询创建组合索引
- 定期 VACUUM 和 ANALYZE
- 考虑分区表策略（按租户或时间）

**缓存策略：**
- Go 层使用 Redis 缓存热点数据
- TeslaMate 使用 ETS 缓存 Token 和车辆状态
- 设置合理的 TTL 避免脏读

#### 5.2 监控与日志

**TeslaMate 监控：**
- 暴露 Prometheus metrics 端点
- 监控租户进程数量和资源占用
- 告警：Token 刷新失败、车辆监控异常

**Go 服务监控：**
- API 响应时间和错误率
- 数据库查询性能
- 租户活跃度统计

**日志聚合：**
- TeslaMate 日志输出 JSON 格式
- Go 日志统一格式
- 使用 ELK 或类似工具集中收集

#### 5.3 安全加固

**Token 安全：**
- 确保 `ENCRYPTION_KEY` 足够随机且安全存储
- 定期轮换加密密钥（需要重新加密现有 Token）
- 限制 Token 访问权限

**API 安全：**
- 所有 API 启用 HTTPS
- 实施速率限制防止滥用
- 输入验证和 SQL 注入防护

**租户隔离审计：**
- 定期审计数据库查询是否包含租户过滤
- 自动化测试覆盖跨租户访问场景
- 敏感操作记录审计日志

#### 5.4 扩展性考虑

**水平扩展：**
- TeslaMate 可部署多个实例（需要租户分配策略）
- 使用 Erlang Distribution 或 Consul 实现服务发现
- 租户与实例的映射关系持久化

**数据归档：**
- 定期归档历史数据到冷存储
- 保留租户最近 N 个月的热数据
- 提供历史数据查询接口

**多区域部署：**
- 根据租户地理位置就近部署
- 数据复制与同步策略
- 跨区域请求路由

## 技术风险与缓解

### 风险一：租户隔离不彻底

**风险描述：** 代码漏洞导致跨租户数据泄露

**缓解措施：**
- 数据库层面设置行级安全策略（RLS）
- 代码审查强制检查租户过滤
- 自动化测试覆盖隔离场景
- 定期安全审计和渗透测试

### 风险二：性能瓶颈

**风险描述：** 租户数量增长导致数据库或进程管理性能下降

**缓解措施：**
- 设计初期进行压力测试
- 监控系统性能指标
- 预留水平扩展能力
- 合理配置资源限制

### 风险三：迁移数据丢失

**风险描述：** 数据库模式变更或代码改造导致数据丢失

**缓解措施：**
- 每次变更前完整备份数据库
- 在测试环境完整验证迁移脚本
- 提供回滚方案
- 分步迁移，每步可验证

### 风险四：TeslaMate 与 Go 集成复杂度

**风险描述：** 跨语言、跨进程通信增加系统复杂度和故障点

**缓解措施：**
- 优先使用共享数据库模式简化集成
- 明确职责边界，避免循环依赖
- 提供完善的接口文档和示例
- 增加集成测试覆盖

## 实施建议

### 迭代开发原则

**每阶段独立可测：**
- 阶段一完成后确保 TeslaMate 精简版可正常运行
- 阶段二完成后验证多租户 Token 管理
- 阶段三完成后测试租户隔离效果
- 阶段四完成后进行端到端集成测试

**保留回滚能力：**
- 使用 Git 分支管理每个阶段的代码
- 数据库迁移提供 down 脚本
- 关键配置可通过环境变量切换

**渐进式上线：**
- 先在测试环境完整验证
- 小规模灰度发布（少量租户）
- 监控稳定后全量上线

### 测试策略

**单元测试：**
- TeslaMate 核心模块（Api, Vehicles, Tenants）
- Go 业务逻辑（租户管理、数据查询）
- 覆盖率目标 > 80%

**集成测试：**
- TeslaMate 与 Tesla API 交互（使用 Mock）
- Go 与数据库交互
- TeslaMate 与 Go 跨层调用

**端到端测试：**
- 租户创建到数据采集完整流程
- 多租户并发场景
- 故障恢复测试

**性能测试：**
- 模拟 100 个租户同时在线
- 数据库查询响应时间
- 内存和 CPU 使用率

## 交付物清单

### 设计文档

- [ ] 本设计方案文档
- [ ] 数据库 Schema 设计文档（包含 ER 图）
- [ ] API 接口规范文档
- [ ] 部署架构图

### 代码实现

- [ ] TeslaMate 精简版代码（阶段一）
- [ ] 多租户 Token 管理模块（阶段二）
- [ ] 租户监督树实现（阶段三）
- [ ] Go + Gin API 服务代码（阶段四）

### 数据库脚本

- [ ] 表结构迁移脚本（Ecto Migration）
- [ ] 索引创建脚本
- [ ] 数据迁移脚本（如有历史数据）

### 测试用例

- [ ] TeslaMate 单元测试
- [ ] Go 业务逻辑测试
- [ ] 集成测试套件
- [ ] 性能测试脚本

### 部署文档

- [ ] Docker Compose 配置示例
- [ ] Kubernetes 部署 YAML（可选）
- [ ] 环境变量配置说明
- [ ] 运维手册

## 时间估算

| 阶段 | 工作内容 | 预估工时 |
|------|---------|---------|
| 阶段一 | 精简 TeslaMate | 2-3 天 |
| 阶段二 | OAuth 改造 | 5-7 天 |
| 阶段三 | 租户监督树 | 5-7 天 |
| 阶段四 | Go 业务层 | 10-15 天 |
| 阶段五 | 优化与测试 | 5-7 天 |
| **总计** | **全部阶段** | **27-39 天** |

备注：以上为单人全职开发的预估，实际时间根据团队规模和技能熟练度调整
