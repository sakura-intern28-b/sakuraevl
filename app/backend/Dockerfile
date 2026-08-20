FROM --platform=$BUILDPLATFORM golang:1.25.12-alpine3.24 AS builder
WORKDIR /app

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -trimpath -ldflags="-s -w" -o /out/sakuravel ./cmd/api/

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

EXPOSE 8080
CMD ["/usr/local/bin/sakuravel"]
