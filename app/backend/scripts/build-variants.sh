#!/usr/bin/env bash
# 性能比較用に backend イメージを2種類ビルドしてコンテナレジストリへ push する。
#
#   baseline  … 性能改善前のアプリコード（一覧APIのN+1あり / 集計テーブル未使用）
#   optimized … 性能改善後のアプリコード
#
# どちらも「現在のトレース計装 (internal/telemetry, otelhttp)」を含む。
# 改善前の当時のコミットには計装が無く、そのまま焼いてもトレースが
# 一切送信されないため、アプリコードだけを当時の内容へ戻して焼いている。
#
# 使い方:
#   docker login <レジストリのホスト名>
#   REGISTRY_URL=intern28-b.sakuracr.jp ./scripts/build-variants.sh
#   REGISTRY_URL=... ./scripts/build-variants.sh baseline   # 片方だけ
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
IMAGE_NAME="${IMAGE_NAME:-intern2026-app-backend}"

: "${REGISTRY_URL:?REGISTRY_URL を指定してください (例: REGISTRY_URL=intern28-b.sakuracr.jp)}"

# baseline を焼くためのブランチ。scripts/make-baseline-branch.sh が作る。
BASELINE_REF="${BASELINE_REF:-perf/baseline-app}"
OPTIMIZED_REF="${OPTIMIZED_REF:-HEAD}"

if [ "$#" -eq 0 ]; then
  targets=(baseline optimized)
else
  targets=("$@")
fi

WORKTREE=""
cleanup() {
  if [ -n "$WORKTREE" ]; then
    git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    WORKTREE=""
  fi
}
trap cleanup EXIT

build_from_ref() {
  local ref="$1" tag="$2" sha
  sha="$(git -C "$REPO_ROOT" rev-parse --short "$ref")"

  echo "==> ${tag}: ${ref} (${sha}) をビルドします"
  WORKTREE="$(mktemp -d)"
  # mktemp が作った空ディレクトリには worktree add できないため一度消す
  rmdir "$WORKTREE"
  git -C "$REPO_ROOT" worktree add --detach --quiet "$WORKTREE" "$ref"

  docker buildx build \
    --platform linux/amd64 \
    -t "${REGISTRY_URL}/${IMAGE_NAME}:${tag}" \
    -t "${REGISTRY_URL}/${IMAGE_NAME}:${tag}-${sha}" \
    --push \
    "$WORKTREE/app/backend"

  cleanup
  echo "==> push 完了: ${REGISTRY_URL}/${IMAGE_NAME}:${tag} , :${tag}-${sha}"
}

for t in "${targets[@]}"; do
  case "$t" in
    baseline)  build_from_ref "$BASELINE_REF"  baseline  ;;
    optimized) build_from_ref "$OPTIMIZED_REF" optimized ;;
    *) echo "不明なターゲット: $t (baseline | optimized)" >&2; exit 1 ;;
  esac
done
