#!/usr/bin/env bash
# api コンテナのイメージだけを差し替えて、性能改善前後を比較できるようにする。
# db / proxy / frontend はそのまま動き続けるため、切り替えは数秒で終わる。
#
# 使い方（app/backend で実行）:
#   ./scripts/switch-variant.sh baseline     # 改善前のアプリに切り替え
#   ./scripts/switch-variant.sh optimized    # 改善後のアプリに切り替え
#   ./scripts/switch-variant.sh status       # いま動いているタグを表示
#
# 任意のタグも指定できる:
#   ./scripts/switch-variant.sh baseline-1ae4571
#
# 切り替えたタグは service.version リソース属性としてトレースに載るので、
# モニタリングスイート側で service.version ごとに応答時間を比較できる。
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BACKEND_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-compose.reg.yml}"
VARIANT_ENV_FILE=".env.variant"

env_file_args=()
[ -f .env ] && env_file_args+=(--env-file .env)
[ -f "$VARIANT_ENV_FILE" ] && env_file_args+=(--env-file "$VARIANT_ENV_FILE")

compose() {
  docker compose -f "$COMPOSE_FILE" "${env_file_args[@]}" "$@"
}

usage() {
  echo "使い方: $0 {baseline|optimized|<タグ名>|status}" >&2
  exit 1
}

[ "$#" -ge 1 ] || usage
target="$1"

if [ "$target" = "status" ]; then
  echo "compose file : $COMPOSE_FILE"
  if [ -f "$VARIANT_ENV_FILE" ]; then
    echo "選択中のタグ : $(grep -E '^BACKEND_TAG=' "$VARIANT_ENV_FILE" | cut -d= -f2-)"
  else
    echo "選択中のタグ : (未設定 → compose の既定値 latest)"
  fi
  echo "稼働中の api :"
  compose ps api
  docker inspect --format '  image = {{.Config.Image}}' \
    "$(compose ps -q api 2>/dev/null)" 2>/dev/null || true
  exit 0
fi

case "$target" in
  -h|--help|help) usage ;;
esac

# 選択したタグを永続化する。terraform が .env を再生成しても消えないよう、
# .env とは別ファイルに書き、compose には両方を渡す。
printf 'BACKEND_TAG=%s\n' "$target" > "$VARIANT_ENV_FILE"
env_file_args=()
[ -f .env ] && env_file_args+=(--env-file .env)
env_file_args+=(--env-file "$VARIANT_ENV_FILE")

echo "==> backend イメージのタグを '${target}' に切り替えます"
compose pull api
compose up -d --no-deps api

echo "==> 切り替え完了"
compose ps api

cat <<MSG

トレース側では service.version="${target}" として記録されます。
比較の手順:
  1) 切り替え直後は数十秒〜数分ほど負荷をかけてトレースを溜める
  2) モニタリングスイートで service.version ごとにエンドポイント別の
     応答時間（p50/p95）を比較する

注意: DBのインデックスと集計テーブル (migrations 002〜004) は
      アプリを戻しても残ります。純粋な当時の性能を測る場合は
      docs/perf-compare.md の「DBも含めて戻す」を参照してください。
MSG
