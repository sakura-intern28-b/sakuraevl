#!/bin/bash
set -e

# 初回のSSL証明書を取得するスクリプト。
# 対象ドメインとメールアドレスは infra/terraform が生成した .env
# (APP_DOMAIN / CERTBOT_EMAIL) から読み取るため、このファイルに
# ドメインを直接書く必要はない。
# 環境変数 DOMAIN / EMAIL を与えればそちらが優先される。

cd "$(dirname "$0")"

# .env は DATABASE_URL などに () や & を含むため source せず、必要な行だけ取り出す
env_value() {
  [ -f .env ] || return 0
  sed -n "s/^$1=//p" .env | tail -n 1
}

DOMAIN="${DOMAIN:-$(env_value APP_DOMAIN)}"
EMAIL="${EMAIL:-$(env_value CERTBOT_EMAIL)}"

if [ -z "$DOMAIN" ]; then
  echo "APP_DOMAIN (app_domain) が未設定のため、証明書は取得できません。" >&2
  echo "IPアドレスでの公開はHTTPのみとなります。" >&2
  exit 1
fi

EMAIL="${EMAIL:-admin@${DOMAIN}}"

echo "=== 0. 対象ドメイン: ${DOMAIN} (通知先: ${EMAIL}) ==="

echo "=== 1. 既存の proxy を停止してポート80を解放します ==="
docker compose -f compose.reg.yml stop proxy || true

echo "=== 2. Standaloneモードで初回のSSL証明書を取得します ==="
docker run --rm \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -p 80:80 \
  certbot/certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN"

echo "=== 3. Nginx(proxy)とCertbotを起動します ==="
docker compose -f compose.reg.yml up -d proxy certbot

echo "=== 完了! HTTPSでのアクセスが可能です。 ==="
