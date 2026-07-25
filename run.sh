#!/bin/bash
# ============================================================
# run.sh — 一键启动全部服务（基础设施 + 8 个 Go 微服务）
#
# 用法: ./run.sh              # 启动全部
#       ./run.sh infra        # 仅启动基础设施
#       ./run.sh build        # 仅编译
#       ./run.sh services     # 仅启动 Go 服务
#       ./run.sh stop         # 停止全部
# ============================================================
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
LOG_DIR="$PROJECT_DIR/logs"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

MYSQL_PORT=3307
REDIS_PORT=16379
ETCD_PORT=12379

PIDS=()

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ============================================================
# 基础设施
# ============================================================
start_infra() {
    log_step "启动基础设施..."

    if docker ps --format '{{.Names}}' | grep -q '^mall-mysql$'; then
        log_info "MySQL 已在运行"
    else
        docker rm -f mall-mysql 2>/dev/null || true
        docker run -d --name mall-mysql \
            -p $MYSQL_PORT:3306 \
            -e MYSQL_ROOT_PASSWORD=123456 \
            mysql:8.0 --default-authentication-plugin=mysql_native_password
        log_info "MySQL 已启动 (127.0.0.1:$MYSQL_PORT)"
    fi

    if docker ps --format '{{.Names}}' | grep -q '^mall-redis$'; then
        log_info "Redis 已在运行"
    else
        docker rm -f mall-redis 2>/dev/null || true
        docker run -d --name mall-redis -p $REDIS_PORT:6379 redis:7-alpine
        log_info "Redis 已启动 (127.0.0.1:$REDIS_PORT)"
    fi

    if docker ps --format '{{.Names}}' | grep -q '^mall-etcd$'; then
        log_info "Etcd 已在运行"
    else
        docker rm -f mall-etcd 2>/dev/null || true
        docker run -d --name mall-etcd \
            -p $ETCD_PORT:2379 \
            -e ALLOW_NONE_AUTHENTICATION=yes \
            quay.io/coreos/etcd:v3.5.21 \
            /usr/local/bin/etcd \
            --name mall-etcd \
            --listen-client-urls http://0.0.0.0:2379 \
            --advertise-client-urls http://127.0.0.1:2379
        log_info "Etcd 已启动 (127.0.0.1:$ETCD_PORT)"
    fi

    # 等待就绪
    log_info "等待 MySQL 就绪..."
    until docker exec mall-mysql mysqladmin ping -h localhost -u root -p123456 --silent 2>/dev/null; do sleep 1; done
    log_info "等待 Redis 就绪..."
    until docker exec mall-redis redis-cli ping 2>/dev/null | grep -q PONG; do sleep 1; done
    log_info "等待 Etcd 就绪..."
    until curl -s "http://127.0.0.1:$ETCD_PORT/version" >/dev/null 2>&1; do sleep 1; done

    log_info "基础设施全部就绪"
}

# ============================================================
# 初始化数据库
# ============================================================
init_db() {
    log_step "初始化数据库..."
    docker exec -i mall-mysql mysql -u root -p123456 < "$PROJECT_DIR/deploy/initdb/init.sql"
    log_info "数据库初始化完成 (mall)"
}

# ============================================================
# 编译
# ============================================================
build_all() {
    log_step "编译服务..."
    mkdir -p "$BUILD_DIR"

    local services=(
        "user-rpc|service/user/rpc"
        "user-api|service/user/api"
        "product-rpc|service/product/rpc"
        "product-api|service/product/api"
        "order-rpc|service/order/rpc"
        "order-api|service/order/api"
        "pay-rpc|service/pay/rpc"
        "pay-api|service/pay/api"
    )

    for entry in "${services[@]}"; do
        local name="${entry%%|*}"
        local path="${entry##*|}"
        echo -n "  $name ... "
        go build -ldflags="-s -w" -o "$BUILD_DIR/$name" "$PROJECT_DIR/$path" && echo "ok" || {
            echo "FAIL"
            log_error "$name 编译失败"
            return 1
        }
    done
    log_info "编译完成 → $BUILD_DIR/"
}

# ============================================================
# 预检 & 修复本地配置（解决开发环境常见问题）
# ============================================================
fix_config() {
    local cfg="$1"
    # Auth: true → Auth: false（开发环境无需 RPC 鉴权）
    sed -i 's/^Auth: true$/Auth: false/' "$cfg" 2>/dev/null || true
    # StrictControl: true → false
    sed -i 's/StrictControl: true/StrictControl: false/' "$cfg" 2>/dev/null || true
}

# ============================================================
# 启动 RPC
# ============================================================
start_rpc() {
    log_step "启动 RPC 服务..."
    mkdir -p "$LOG_DIR"

    local rpcs=(
        "user-rpc|service/user/rpc/etc/user.yaml|9000"
        "product-rpc|service/product/rpc/etc/product.yaml|9001"
        "order-rpc|service/order/rpc/etc/order.yaml|9002"
        "pay-rpc|service/pay/rpc/etc/pay.yaml|9003"
    )

    for entry in "${rpcs[@]}"; do
        IFS='|' read -r name config port <<< "$entry"
        fix_config "$PROJECT_DIR/$config"
        echo -n "  $name (:$port) ... "
        "$BUILD_DIR/$name" -f "$PROJECT_DIR/$config" > "$LOG_DIR/$name.log" 2>&1 &
        echo "pid $!"
        PIDS+=($!)
        sleep 2
    done

    sleep 4
    log_info "RPC 已启动"
}

# ============================================================
# 启动 API
# ============================================================
start_api() {
    log_step "启动 API 服务..."
    mkdir -p "$LOG_DIR"

    local apis=(
        "user-api|service/user/api/etc/user.yaml|8000"
        "product-api|service/product/api/etc/product.yaml|8001"
        "order-api|service/order/api/etc/order.yaml|8002"
        "pay-api|service/pay/api/etc/pay.yaml|8003"
    )

    for entry in "${apis[@]}"; do
        IFS='|' read -r name config port <<< "$entry"
        echo -n "  $name (:$port) ... "
        "$BUILD_DIR/$name" -f "$PROJECT_DIR/$config" > "$LOG_DIR/$name.log" 2>&1 &
        echo "pid $!"
        PIDS+=($!)
        sleep 1
    done

    sleep 2
    log_info "API 已启动"
}

# ============================================================
# 清理
# ============================================================
cleanup() {
    echo ""
    log_warn "正在停止..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    log_info "已停止"
    exit 0
}

stop_all() {
    log_step "停止所有服务..."
    for name in user-rpc user-api product-rpc product-api order-rpc order-api pay-rpc pay-api; do
        pkill -f "build/$name" 2>/dev/null || true
    done
    docker stop mall-mysql mall-redis mall-etcd 2>/dev/null || true
    docker rm mall-mysql mall-redis mall-etcd 2>/dev/null || true
    log_info "全部停止"
}

# ============================================================
# 状态面板
# ============================================================
show_status() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        全部服务启动完成               ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  API:                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    user-api    http://localhost:8000 ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    product-api http://localhost:8001 ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    order-api   http://localhost:8002 ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    pay-api     http://localhost:8003 ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  RPC:                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    user-rpc    :9000                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    product-rpc :9001                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    order-rpc   :9002                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}    pay-rpc     :9003                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Ctrl+C 停止 | logs/ 查看日志        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ./test.sh 测试                      ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# Main
# ============================================================
trap cleanup INT TERM

case "${1:-all}" in
    infra)
        start_infra
        init_db
        ;;
    build)
        build_all
        ;;
    services)
        start_rpc
        start_api
        show_status
        wait
        ;;
    stop)
        stop_all
        exit 0
        ;;
    all)
        start_infra
        init_db
        build_all
        start_rpc
        start_api
        show_status
        wait
        ;;
    *)
        echo "用法: $0 {all|infra|build|services|stop}"
        exit 1
        ;;
esac
