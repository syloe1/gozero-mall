# gozero-learningmall

基于 [go-zero](https://github.com/zeromicro/go-zero) 框架的微服务电商后端系统，包含用户、商品、订单、支付四个业务模块。

## 架构概览

```
 ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
 │ User-API │  │Product-API│  │ Order-API│  │  Pay-API │   ← HTTP (端口 8000-8003)
 │  :8000   │  │  :8001   │  │  :8002   │  │  :8003   │
 └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
      │              │             │             │
      ▼              ▼             ▼             ▼
 ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
 │ User-RPC │  │Product-RPC│  │ Order-RPC│  │  Pay-RPC │   ← gRPC (端口 9000-9003)
 │  :9000   │  │  :9001   │  │  :9002   │  │  :9003   │
 └────┬─────┘  └────┬─────┘  └────┬──┬──┘  └────┬──┬──┘
      │              │             │  │          │  │
      ▼              ▼             │  └──────────┘  │
 ┌──────────┐  ┌──────────┐       │  调用 User-RPC  │
 │  MySQL   │  │  Redis   │       │  和 Product-RPC │
 │  :3307   │  │  :16379  │       │                 │
 └──────────┘  └──────────┘       └────────┬────────┘
      ▲              ▲              调用 User-RPC
      │              │              和 Order-RPC
      └──────┬───────┘
             │
      ┌──────┴──────┐
      │    etcd     │   ← 服务注册发现 (:12379)
      └─────────────┘
```

- **API 层**：对外提供 HTTP REST 接口，负责 JWT 鉴权，通过 gRPC 调用下游 RPC 服务
- **RPC 层**：核心业务逻辑，直接操作数据库和缓存
- **基础设施**：MySQL（持久化）、Redis（缓存）、etcd（服务发现）、Jaeger（链路追踪）

## 技术栈

| 类别       | 技术                                      |
| ---------- | ----------------------------------------- |
| 微服务框架 | go-zero v1.10.2                           |
| HTTP       | go-zero rest（基于 Gin）                   |
| RPC        | go-zero zrpc（基于 gRPC + etcd 服务发现） |
| 数据库     | MySQL 8.0                                 |
| 缓存       | Redis 7                                   |
| 服务发现   | etcd v3.5                                 |
| 链路追踪   | Jaeger + OpenTelemetry                    |
| 监控       | Prometheus                                |
| 认证       | JWT (HS256)                               |
| 密码加密   | scrypt                                    |
| 容器化     | Docker + Docker Compose                   |

## 快速启动（Docker Compose，推荐）

### 前置条件

- [Docker](https://www.docker.com/) 20.10+
- [Docker Compose](https://docs.docker.com/compose/) 2.0+

### 一键启动

```bash
# 1. 克隆项目
git clone <your-repo-url>
cd gozero-learningmall

# 2. 构建镜像并启动所有服务（14 个容器）
docker compose up -d --build

# 3. 查看启动状态
docker compose ps

# 4. 查看日志
docker compose logs -f
```

首次启动会：
1. 构建 Go 二进制文件（多阶段构建，约 2-5 分钟）
2. 启动 MySQL、Redis、etcd、Jaeger
3. 自动初始化数据库表结构（`deploy/initdb/init.sql`）
4. 依次启动 4 个 RPC 服务和 4 个 API 网关

### 验证服务

```bash
# 测试用户注册
curl -X POST http://localhost:8000/api/user/register \
  -H "Content-Type: application/json" \
  -d '{"name":"test","gender":1,"mobile":"13800138000","password":"123456"}'

# 测试用户登录
curl -X POST http://localhost:8000/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"mobile":"13800138000","password":"123456"}'

# Jaeger UI（链路追踪面板）
# 浏览器打开: http://localhost:16686
```

### 停止与清理

```bash
# 停止所有服务
docker compose down

# 停止并删除数据卷（重置数据库）
docker compose down -v
```

## 本地开发

### 前置条件

- Go 1.25+
- MySQL 8.0
- Redis 7
- etcd v3.5
- Jaeger（可选，用于链路追踪）

### 1. 启动基础设施

如果你只想在本地跑 Go 服务，可以用 Docker 单独启动基础设施：

```bash
docker compose up -d mysql redis etcd jaeger
```

这会暴露以下端口：

| 服务   | 端口    |
| ------ | ------- |
| MySQL  | 3307    |
| Redis  | 16379   |
| etcd   | 12379   |
| Jaeger | 16686   |

### 2. 初始化数据库

手动连接 MySQL 并执行初始化脚本：

```bash
# 使用 docker exec 导入
docker exec -i mall-mysql mysql -uroot -p123456 < deploy/initdb/init.sql
```

或者手动连接 `127.0.0.1:3307`（root / 123456），创建 `mall` 数据库并执行 `deploy/initdb/init.sql`。

### 3. 启动服务

每个服务需要单独启动，**RPC 必须先于 API 启动**：

```bash
# 终端 1: 启动 User-RPC
cd service/user/rpc
go run user.go -f etc/user.yaml

# 终端 2: 启动 User-API
cd service/user/api
go run user.go -f etc/user.yaml

# 终端 3: 启动 Product-RPC
cd service/product/rpc
go run product.go -f etc/product.yaml

# 终端 4: 启动 Product-API
cd service/product/api
go run product.go -f etc/product.yaml

# 终端 5: 启动 Order-RPC
cd service/order/rpc
go run order.go -f etc/order.yaml

# 终端 6: 启动 Order-API
cd service/order/api
go run order.go -f etc/order.yaml

# 终端 7: 启动 Pay-RPC
cd service/pay/rpc
go run pay.go -f etc/pay.yaml

# 终端 8: 启动 Pay-API
cd service/pay/api
go run pay.go -f etc/pay.yaml
```

或者编译后运行：

```bash
# 编译
go build -o user-rpc.exe ./service/user/rpc/
go build -o user-api.exe ./service/user/api/
# ... 其他服务同理

# 运行
./user-rpc.exe -f service/user/rpc/etc/user.yaml
./user-api.exe -f service/user/api/etc/user.yaml
```

### 4. 启动顺序

```
MySQL → Redis → etcd
         ↓
   4 个 RPC 服务（user → product → order → pay）
         ↓
   4 个 API 网关
```

Order-RPC 依赖 User-RPC 和 Product-RPC；Pay-RPC 依赖 User-RPC 和 Order-RPC。

## API 端点

所有接口均为 `POST` 请求，`Content-Type: application/json`。

### 用户服务 (User-API :8000)

| 路径                | 说明     | JWT 鉴权 |
| ------------------- | -------- | -------- |
| `/api/user/login`   | 用户登录 | 否       |
| `/api/user/register`| 用户注册 | 否       |
| `/api/user/userinfo`| 获取用户信息 | 是   |

### 商品服务 (Product-API :8001)

| 路径                   | 说明       | JWT 鉴权 |
| ---------------------- | ---------- | -------- |
| `/api/product/create`  | 创建商品   | 是       |
| `/api/product/detail`  | 商品详情   | 是       |
| `/api/product/remove`  | 删除商品   | 是       |
| `/api/product/update`  | 更新商品   | 是       |

### 订单服务 (Order-API :8002)

| 路径                  | 说明       | JWT 鉴权 |
| --------------------- | ---------- | -------- |
| `/api/order/create`   | 创建订单   | 是       |
| `/api/order/detail`   | 订单详情   | 是       |
| `/api/order/list`     | 订单列表   | 是       |
| `/api/order/remove`   | 删除订单   | 是       |
| `/api/order/update`   | 更新订单   | 是       |

### 支付服务 (Pay-API :8003)

| 路径                 | 说明       | JWT 鉴权 |
| -------------------- | ---------- | -------- |
| `/api/pay/callback`  | 支付回调   | 是       |
| `/api/pay/create`    | 创建支付   | 是       |
| `/api/pay/detail`    | 支付详情   | 是       |

## 项目结构

```
gozero-learningmall/
├── common/                     # 公共工具
│   ├── cryptx/                 # scrypt 密码加解密
│   └── jwtx/                   # JWT 令牌生成
├── deploy/                     # 部署配置
│   ├── etc/                    # Docker 环境下的 YAML 配置
│   └── initdb/                 # 数据库初始化 SQL
├── service/
│   ├── user/
│   │   ├── api/                # User HTTP 网关
│   │   │   ├── etc/            # 本地开发配置
│   │   │   └── internal/
│   │   │       ├── config/     # 配置结构体
│   │   │       ├── handler/    # HTTP 处理器
│   │   │       ├── logic/      # 业务逻辑
│   │   │       ├── svc/        # 服务上下文（依赖注入）
│   │   │       └── types/      # 请求/响应类型
│   │   ├── rpc/                # User gRPC 服务
│   │   │   ├── etc/
│   │   │   ├── internal/
│   │   │   ├── types/          # 生成的 protobuf 代码
│   │   │   └── userclient/     # 生成的 gRPC 客户端
│   │   └── model/              # 数据访问层（带 Redis 缓存）
│   ├── product/                # 同上结构
│   ├── order/                  # 同上结构
│   └── pay/                    # 同上结构
├── docker-compose.yml          # Docker Compose 编排
├── Dockerfile                  # 多阶段构建
└── go.mod
```

## 配置说明

### 主要配置项

| 配置项               | 本地开发             | Docker 部署       |
| -------------------- | -------------------- | ----------------- |
| MySQL 连接           | `root:123456@tcp(127.0.0.1:3307)` | `root:123456@tcp(mysql:3306)` |
| Redis 地址           | `127.0.0.1:16379`    | `redis:6379`      |
| etcd 地址            | `127.0.0.1:12379`    | `etcd:2379`        |
| JWT 密钥             | `uOvKLmVfztaXGpNYd4Z0I1SiT7MweJhl` | 同本地 |
| JWT 过期时间         | 86400 秒（24小时）   | 同本地           |
| 数据库名             | `mall`               | `mall`             |

### 本地配置 vs Docker 配置

- **本地开发**：使用 `service/*/{api,rpc}/etc/*.yaml`，连接地址为 `127.0.0.1`
- **Docker 部署**：使用 `deploy/etc/*.yaml`，连接地址为 Docker 容器名（`mysql`、`redis`、`etcd`）

两个环境的配置文件不同，Dockerfile 会将 `deploy/etc/` 下的配置打包进镜像。

## Prometheus 监控端口

| 服务        | Metrics 端口 |
| ----------- | ------------ |
| User-API    | 9080         |
| User-RPC    | 9090         |
| Product-API | 9081         |
| Product-RPC | 9091         |
| Order-API   | 9082         |
| Order-RPC   | 9092         |
| Pay-API     | 9083         |
| Pay-RPC     | 9093         |

## 常见问题

**Q: 启动后某个服务一直在重启？**

```bash
docker compose logs <service-name>  # 查看具体错误日志
```

常见原因：基础设施（MySQL/Redis/etcd）未就绪，等待健康检查通过即可。

**Q: 如何重置数据库？**

```bash
docker compose down -v   # 删除数据卷
docker compose up -d     # 重新启动，自动重建表
```

**Q: 本地开发时数据库连不上？**

确保只启动了基础设施容器：
```bash
docker compose up -d mysql redis etcd jaeger
```

确认端口映射：MySQL → 3307，Redis → 16379，etcd → 12379。
