#!/bin/bash
# ============================================================
# test.sh — 端到端 API 测试
#
# 用法: ./test.sh              # 全部测试
#       ./test.sh user          # 仅用户模块
#       ./test.sh product       # 仅产品模块
# ============================================================

PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 全局状态（模块间共享）
MOBILE="1380000$(date +%s | tail -c5)"
PASSWORD="test123"
TOKEN=""
USER_ID=""
PID=""
OID=""
PAY_ID=""

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL+1)); }

header() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"
}

api() {
    local url="$1" data="$2"
    local hdr=(-H "Content-Type: application/json")
    [ -n "$TOKEN" ] && hdr+=(-H "Authorization: Bearer $TOKEN")
    curl -s -X POST "$url" "${hdr[@]}" -d "$data"
}

# ============================================================
# 用户模块
# ============================================================
test_user() {
    header "用户模块 (:8000)"

    # 注册
    echo -n "  注册 ... "
    resp=$(api "http://localhost:8000/api/user/register" \
        "{\"name\":\"测试用户\",\"gender\":1,\"mobile\":\"$MOBILE\",\"password\":\"$PASSWORD\"}")
    USER_ID=$(echo "$resp" | jq -r '.id // empty')
    if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
        pass "注册成功 id=$USER_ID"
    else
        fail "注册失败" "$resp"; return 1
    fi

    # 登录
    echo -n "  登录 ... "
    resp=$(api "http://localhost:8000/api/user/login" \
        "{\"mobile\":\"$MOBILE\",\"password\":\"$PASSWORD\"}")
    TOKEN=$(echo "$resp" | jq -r '.accessToken // empty')
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
        pass "登录成功"
    else
        fail "登录失败" "$resp"; return 1
    fi

    # 用户信息
    echo -n "  用户信息 ... "
    resp=$(api "http://localhost:8000/api/user/userinfo" '{}')
    if echo "$resp" | jq -e '.mobile' >/dev/null 2>&1; then
        pass "获取成功 mobile=$(echo "$resp" | jq -r '.mobile')"
    else
        fail "获取失败" "$resp"
    fi
}

# ============================================================
# 产品模块
# ============================================================
test_product() {
    header "产品模块 (:8001)"

    [ -z "$TOKEN" ] && { fail "跳过" "无 Token"; return; }

    # 创建
    echo -n "  创建 ... "
    resp=$(api "http://localhost:8001/api/product/create" \
        '{"name":"测试商品","desc":"描述","stock":100,"amount":9900,"status":1}')
    PID=$(echo "$resp" | jq -r '.id // empty')
    if [ -n "$PID" ] && [ "$PID" != "null" ]; then
        pass "创建成功 id=$PID"
    else
        fail "创建失败" "$resp"; return 1
    fi

    # 详情
    echo -n "  详情 ... "
    resp=$(api "http://localhost:8001/api/product/detail" "{\"id\":$PID}")
    if echo "$resp" | jq -e '.name' >/dev/null 2>&1; then
        pass "查询成功 name=$(echo "$resp" | jq -r '.name')"
    else
        fail "查询失败" "$resp"
    fi

    # 更新
    echo -n "  更新 ... "
    resp=$(api "http://localhost:8001/api/product/update" \
        "{\"id\":$PID,\"name\":\"更新商品\",\"stock\":200,\"amount\":8800,\"status\":1}")
    if [ -z "$resp" ] || [ "$resp" = "{}" ]; then
        pass "更新成功"
    else
        fail "更新失败" "$resp"
    fi
}

# ============================================================
# 订单模块
# ============================================================
test_order() {
    header "订单模块 (:8002)"

    [ -z "$TOKEN" ] && { fail "跳过" "无 Token"; return; }

    uid=${USER_ID:-1}
    pid=${PID:-1}

    # 创建
    echo -n "  创建 ... "
    resp=$(api "http://localhost:8002/api/order/create" \
        "{\"uid\":$uid,\"pid\":$pid,\"amount\":9900,\"status\":0}")
    OID=$(echo "$resp" | jq -r '.id // empty')
    if [ -n "$OID" ] && [ "$OID" != "null" ]; then
        pass "创建成功 id=$OID"
    else
        fail "创建失败" "$resp"; return 1
    fi

    # 详情
    echo -n "  详情 ... "
    resp=$(api "http://localhost:8002/api/order/detail" "{\"id\":$OID}")
    if echo "$resp" | jq -e '.amount' >/dev/null 2>&1; then
        pass "查询成功 amount=$(echo "$resp" | jq -r '.amount')"
    else
        fail "查询失败" "$resp"
    fi

    # 列表
    echo -n "  列表 ... "
    resp=$(api "http://localhost:8002/api/order/list" "{\"uid\":$uid}")
    if echo "$resp" | jq -e '.[0]' >/dev/null 2>&1; then
        pass "列表成功 $(echo "$resp" | jq 'length') 条"
    else
        fail "列表失败" "$resp"
    fi
}

# ============================================================
# 支付模块
# ============================================================
test_pay() {
    header "支付模块 (:8003)"

    [ -z "$TOKEN" ] && { fail "跳过" "无 Token"; return; }

    uid=${USER_ID:-1}
    oid=${OID:-1}

    # 创建
    echo -n "  创建支付 ... "
    resp=$(api "http://localhost:8003/api/pay/create" \
        "{\"uid\":$uid,\"oid\":$oid,\"amount\":9900}")
    PAY_ID=$(echo "$resp" | jq -r '.id // empty')
    if [ -n "$PAY_ID" ] && [ "$PAY_ID" != "null" ]; then
        pass "创建成功 id=$PAY_ID"
    else
        fail "创建失败" "$resp"; return 1
    fi

    # 详情
    echo -n "  支付详情 ... "
    resp=$(api "http://localhost:8003/api/pay/detail" "{\"id\":$PAY_ID}")
    if echo "$resp" | jq -e '.amount' >/dev/null 2>&1; then
        pass "查询成功 amount=$(echo "$resp" | jq -r '.amount')"
    else
        fail "查询失败" "$resp"
    fi

    # 回调
    echo -n "  支付回调 ... "
    resp=$(api "http://localhost:8003/api/pay/callback" \
        "{\"id\":$PAY_ID,\"uid\":$uid,\"oid\":$oid,\"amount\":9900,\"source\":1,\"status\":1}")
    if [ -z "$resp" ] || [ "$resp" = "{}" ]; then
        pass "回调成功"
    else
        fail "回调失败" "$resp"
    fi
}

# ============================================================
# 统计
# ============================================================
summary() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  结果: ${GREEN}$PASS 通过${NC} / ${RED}$FAIL 失败${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    [ "$FAIL" -gt 0 ] && exit 1
    exit 0
}

trap summary EXIT

case "${1:-all}" in
    user)    test_user ;;
    product) test_product ;;
    order)   test_order ;;
    pay)     test_pay ;;
    all)
        test_user   || true
        test_product || true
        test_order   || true
        test_pay     || true
        ;;
    *) echo "用法: $0 {all|user|product|order|pay}"; exit 1 ;;
esac
