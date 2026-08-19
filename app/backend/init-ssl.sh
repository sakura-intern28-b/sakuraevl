#!/bin/bash
set -e

DOMAIN="teamb.intern28.sakuraha.jp"
EMAIL="admin@teamb.intern28.sakuraha.jp"

echo "=== 1. 既存の proxy を停止してポート80を解放します ==="
docker compose -f compose.reg.yml stop proxy || true

echo "=== 2. Standaloneモードで初回のSSL証明書を取得します ==="
docker run -it --rm \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -p 8080:80 \
  certbot/certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN"

echo "=== 3. Nginx(proxy)とCertbotを起動します ==="
docker compose -f compose.reg.yml up -d proxy certbot

echo "=== 完了! HTTPSでのアクセスが可能です。 ==="
