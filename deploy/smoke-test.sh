#!/usr/bin/env bash
# 端到端冒烟测试：注册 -> 登录 -> 用户信息 -> 商品 -> 订单 -> 支付 -> 回调
# 用法：bash deploy/smoke-test.sh
set -euo pipefail

USER_API="${USER_API:-http://localhost:8000}"
PRODUCT_API="${PRODUCT_API:-http://localhost:8001}"
ORDER_API="${ORDER_API:-http://localhost:8888}"
PAY_API="${PAY_API:-http://localhost:8003}"

MOBILE="139$(date +%s | tail -c 9)"
PASSWORD="123456"
TOKEN=""

api() { # api <base> <path> [json]
  local base="$1" path="$2" body="${3:-}"
  local args=(-sS -X POST "$base$path" -H "Content-Type: application/json")
  [ -n "$TOKEN" ] && args+=(-H "Authorization: Bearer $TOKEN")
  [ -n "$body" ] && args+=(-d "$body")
  curl "${args[@]}"
}

step()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
ok()    { printf '\033[1;32mOK\033[0m   %s\n' "$*"; }
fail()  { printf '\033[1;31mFAIL\033[0m %s\n  %s\n' "$1" "${2:-}"; exit 1; }
need()  { grep -q "$2" <<<"$1" || fail "$3" "$1"; ok "$3"; }
num()   { sed -n 's/.*"'"$1"'":\([0-9]*\).*/\1/p' <<<"$2"; }
str()   { sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p' <<<"$2"; }

step "1. 注册 $MOBILE"
R=$(api "$USER_API" /api/user/register "{\"name\":\"smoke\",\"gender\":1,\"mobile\":\"$MOBILE\",\"password\":\"$PASSWORD\"}")
need "$R" '"id"' "注册成功"
USER_ID=$(num id "$R")
[ -n "$USER_ID" ] || fail "解析 user id 失败" "$R"
echo "     user id = $USER_ID"

step "2. 登录"
R=$(api "$USER_API" /api/user/login "{\"mobile\":\"$MOBILE\",\"password\":\"$PASSWORD\"}")
need "$R" 'accessToken' "登录成功"
TOKEN=$(str accessToken "$R")
[ -n "$TOKEN" ] || fail "解析 token 失败" "$R"
echo "     token = ${TOKEN:0:24}..."

step "3. 未带 token 应被拒绝"
CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$ORDER_API/api/order/detail" \
  -H "Content-Type: application/json" -d '{"id":1}')
[ "$CODE" = "401" ] && ok "401 未授权（JWT 生效）" || fail "期望 401，实际 $CODE"

step "4. 用户信息"
R=$(api "$USER_API" /api/user/userinfo)
need "$R" "\"mobile\":\"$MOBILE\"" "userinfo 与注册手机号一致"

step "5. 创建商品"
R=$(api "$PRODUCT_API" /api/product/create '{"name":"smoke-phone","desc":"test","stock":10,"amount":1999,"status":1}')
need "$R" '"id"' "商品创建成功"
PID=$(num id "$R")

step "6. 商品详情（库存 10）"
R=$(api "$PRODUCT_API" /api/product/detail "{\"id\":$PID}")
need "$R" '"stock":10' "库存为 10"

step "7. 创建订单（status=0 待支付）"
R=$(api "$ORDER_API" /api/order/create "{\"uid\":$USER_ID,\"pid\":$PID,\"amount\":1999,\"status\":0}")
need "$R" '"id"' "订单创建成功"
OID=$(num id "$R")

R=$(api "$ORDER_API" /api/order/detail "{\"id\":$OID}")
need "$R" '"status":0' "订单初始状态为 0"

step "8. 商品库存应扣减为 9（rpc 间调用 + RPC 鉴权）"
R=$(api "$PRODUCT_API" /api/product/detail "{\"id\":$PID}")
need "$R" '"stock":9' "库存扣减 10 -> 9"

step "9. 订单列表"
R=$(api "$ORDER_API" /api/order/list "{\"uid\":$USER_ID}")
need "$R" "\"id\":$OID" "列表包含新订单"

step "10. 创建支付"
R=$(api "$PAY_API" /api/pay/create "{\"uid\":$USER_ID,\"oid\":$OID,\"amount\":1999}")
need "$R" '"id"' "支付单创建成功"
PAY_ID=$(num id "$R")

step "11. 支付回调 -> 订单状态置为已支付"
R=$(api "$PAY_API" /api/pay/callback "{\"id\":$PAY_ID,\"uid\":$USER_ID,\"oid\":$OID,\"amount\":1999,\"source\":1,\"status\":1}")
grep -q '"msg"' <<<"$R" && fail "支付回调失败" "$R"
ok "支付回调成功"

R=$(api "$ORDER_API" /api/order/detail "{\"id\":$OID}")
need "$R" '"status":1' "订单状态 0 -> 1（回调生效）"

step "12. 修改商品（库存改为 5）"
R=$(api "$PRODUCT_API" /api/product/update "{\"id\":$PID,\"name\":\"smoke-phone\",\"desc\":\"test\",\"stock\":5,\"amount\":1999,\"status\":1}")
grep -q '"msg"' <<<"$R" && fail "商品修改失败" "$R"
R=$(api "$PRODUCT_API" /api/product/detail "{\"id\":$PID}")
need "$R" '"stock":5' "商品库存已改为 5"

step "13. 删除商品"
R=$(api "$PRODUCT_API" /api/product/remove "{\"id\":$PID}")
grep -q '"msg"' <<<"$R" && fail "商品删除失败" "$R"
ok "商品删除成功"

printf '\n\033[1;32m全部通过 ✅\033[0m\n'
