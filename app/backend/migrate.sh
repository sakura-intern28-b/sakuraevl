#!/bin/bash
# schema_migrations テーブルで適用済みバージョンを記録し、
# /migrations 配下の未適用ファイルだけをファイル名昇順で適用する。
# パスワードは呼び出し側で MYSQL_PWD 環境変数として渡す想定。
set -eu

: "${DB_HOST:?}" "${DB_PORT:?}" "${DB_USERNAME:?}" "${DB_NAME:?}"

client() {
  mariadb -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USERNAME}" "${DB_NAME}" "$@"
}

client -e "
  CREATE TABLE IF NOT EXISTS schema_migrations (
      version    VARCHAR(255) PRIMARY KEY,
      applied_at TIMESTAMP NOT NULL DEFAULT NOW()
  );
"

set -- /migrations/*.sql
if [ ! -e "$1" ]; then
  echo "/migrations に *.sql が見つかりません (マウントが空です)" >&2
  exit 1
fi

for f in "$@"; do
  version=$(basename "$f")
  applied=$(client -N -e "SELECT COUNT(*) FROM schema_migrations WHERE version = '${version}'")

  if [ "$applied" != "0" ]; then
    echo "skip ${version} (already applied)"
    continue
  fi

  echo "applying ${version}"
  client < "$f"
  client -e "INSERT INTO schema_migrations (version) VALUES ('${version}')"
done

echo "migrations complete"
