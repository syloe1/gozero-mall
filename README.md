# gozero-mall

> 📚 学习项目：基于 go-zero 微服务框架的电商 mall，参考教程仓库：[nivin-studio/go-zero-mall](https://github.com/nivin-studio/go-zero-mall)
> 本仓库是学习实践仓库，学完基础流程后，会自行新增、扩展功能。

---

## 🐳 Docker 一键启动（推荐）

只需要安装 **Docker Desktop**（Windows / macOS）或 Docker Engine + Compose 插件（Linux），
然后在仓库根目录执行：

```bash
docker compose up -d --build
```

首次启动会自动完成：

- 启动 etcd / MySQL / Redis
- 创建 `mall` 数据库和 4 张业务表（`user`、`product`、`order`、`pay`）
- 把 user.rpc 的 RPC 鉴权 token 写入 Redis
- 编译并启动 8 个 Go 服务（4 个 api + 4 个 rpc）

> 第一次需要下载镜像 + 编译，约 2~5 分钟；之后启动只需几秒。

查看启动状态：

```bash
docker compose ps
```

全部 `running` 即可。查看某个服务日志：

```bash
docker compose logs -f user-api
```

停止（保留数据）：

```bash
docker compose down
```

停止并**清空 MySQL/Redis/etcd 数据**（想重置环境时用）：

```bash
docker compose down -v
```

---

## 服务端口

| 服务 | 地址 | 说明 |
| ---- | ---- | ---- |
| user-api | http://localhost:8000 | 用户注册 / 登录 / 用户信息 |
| product-api | http://localhost:8001 | 商品增删改查 |
| order-api | http://localhost:8888 | 订单增删改查 / 列表 |
| pay-api | http://localhost:8003 | 支付创建 / 详情 / 回调 |

除注册、登录外，其余接口都需要在请求头带 JWT：

```
Authorization: Bearer <login 返回的 token>
```

> 如果本机端口被占用，改 `docker-compose.yml` 里 `ports` 的**左边**（如 `"18000:8000"`）即可。

---

## ✅ 启动后自检

```bash
bash deploy/smoke-test.sh
```

脚本会真实跑一遍完整链路：

1. 注册 → 2. 登录拿 token → 3. 无 token 请求应返回 401 → 4. 查用户信息
5. 创建商品 → 6. 查详情 → 7. 创建订单（status=0）→ 8. 商品库存扣减
9. 订单列表 → 10. 创建支付 → 11. 支付回调 → 订单状态变 1
12. 修改商品 → 13. 删除商品

最后输出 `全部通过 ✅` 就说明 4 个 api + 4 个 rpc（含跨服务 RPC 鉴权）都正常。

---

## API 速查（给前端）

### 1. 注册

```bash
curl -X POST http://localhost:8000/api/user/register \
  -H "Content-Type: application/json" \
  -d '{"name":"alice","gender":1,"mobile":"13800000001","password":"123456"}'
```

### 2. 登录，拿 token

```bash
curl -X POST http://localhost:8000/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"mobile":"13800000001","password":"123456"}'
```

返回示例：

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs...",
  "accessExpire": 1760000000
}
```

之后所有请求都要带上：

```
Authorization: Bearer <accessToken>
Content-Type: application/json
```

> ⚠️ 本项目所有接口都是 **POST + JSON body**（包括 detail / list）。

### 3. 用户信息

```bash
curl -X POST http://localhost:8000/api/user/userinfo \
  -H "Authorization: Bearer <token>"
```

### 4. 商品（8001）

```bash
# 新建
curl -X POST http://localhost:8001/api/product/create \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"name":"iPhone","desc":"手机","stock":10,"amount":6999,"status":1}'

# 详情
curl -X POST http://localhost:8001/api/product/detail \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"id":1}'

# 修改（stock 必填，其余可选）
curl -X POST http://localhost:8001/api/product/update \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"id":1,"name":"iPhone 16","desc":"新手机","stock":8,"amount":6999,"status":1}'
```

### 5. 订单（8888）

```bash
# 新建
curl -X POST http://localhost:8888/api/order/create \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"uid":1,"pid":1,"amount":6999,"status":1}'

# 列表
curl -X POST http://localhost:8888/api/order/list \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"uid":1}'
```

### 6. 支付（8003）

```bash
# 创建支付
curl -X POST http://localhost:8003/api/pay/create \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"uid":1,"oid":1,"amount":6999}'

# 支付回调（模拟第三方回调，成功后订单会被标记为已支付）
curl -X POST http://localhost:8003/api/pay/callback \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"id":1,"uid":1,"oid":1,"amount":6999,"source":1,"status":1}'
```

> 具体字段以各服务 `*.api` 文件为准。

---

## 本地开发（不用 Docker）

需要自行准备 MySQL、Redis、etcd，并修改各服务 `etc/*.yaml` 里的连接地址，然后：

```bash
# 例：启动 user rpc
cd service/user/rpc && go run user.go -f etc/user.yaml

# 例：启动 user api
cd service/user/api && go run user.go -f etc/user.yaml
```

RPC 鉴权开启时，需要手动把 token 写入 Redis：

```bash
redis-cli HSET rpc:auth:user userapi 6jKNZbEpYGeUMAifz10gOnmoty3TV
```
