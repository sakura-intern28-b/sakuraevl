FROM --platform=$BUILDPLATFORM golang:1.25.12-alpine3.24 AS builder
WORKDIR /app

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -trimpath -ldflags="-s -w" -o /out/sakuravel ./cmd/api/

# seed/main.go もここでビルドしておき、実行イメージにはバイナリだけを置く。
# (Goツールチェーンを実行イメージに入れると数百MB増えるため)
RUN go build -trimpath -ldflags="-s -w" -o /out/seed ./seed/

FROM alpine:3.24.1

# CI から渡されるビルド時点のコミットSHA。タグ (latest 等) は可変で
# 後から中身が変わるため、トレースの service.version に SHA を含めて
# 「どのコミットのアプリか」をイメージ自体に焼き込む。
ARG GIT_SHA=unknown
ENV APP_GIT_SHA=${GIT_SHA}
RUN apk add --no-cache ca-certificates tzdata && \
    rm -rf /var/cache/apk/*

WORKDIR /app
COPY --from=builder /out/sakuravel /usr/local/bin/sakuravel

########################################
# シードデータ投入 (seed/main.go のビルド済みバイナリ)
########################################
# VM 上での使い方:
#   ssh <VM> → cd /opt/app
#   docker compose -f compose.reg.yml exec api sh
#   cd /app/seed && ./seed -scale 1
# 接続先は api コンテナの環境変数 DATABASE_URL がそのまま使われる。
# 元ソースも同じディレクトリに置いてあるので、パラメータ確認はこちらを参照。
COPY --from=builder /out/seed /app/seed/seed
COPY --from=builder /app/seed/main.go /app/seed/main.go

EXPOSE 8080
CMD ["/usr/local/bin/sakuravel"]
