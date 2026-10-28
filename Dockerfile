# syntax=docker/dockerfile:1

########## build ##########
FROM golang:1.27-alpine AS builder

ENV GOPROXY=https://goproxy.cn,direct \
    CGO_ENABLED=0 \
    GOOS=linux

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN set -e; \
    mkdir -p /out; \
    for svc in \
        user/api user/rpc \
        product/api product/rpc \
        order/api order/rpc \
        pay/api pay/rpc; do \
        name=$(echo "$svc" | tr '/' '-'); \
        echo ">>> building $name"; \
        go build -trimpath -ldflags="-s -w" -o "/out/$name" "./service/$svc"; \
    done

########## runtime ##########
FROM alpine:3.20

# tzdata: DSN 里 loc=Asia/Shanghai 需要时区数据库；ca-certificates: 出站 HTTPS
RUN apk add --no-cache ca-certificates tzdata

ENV TZ=Asia/Shanghai
WORKDIR /app

COPY --from=builder /out/ /app/
COPY deploy/etc/ /app/etc/

# 具体启动哪个服务由 docker compose 的 command 指定
CMD ["/bin/sh"]
