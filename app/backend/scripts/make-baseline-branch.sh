#!/usr/bin/env bash
# 性能比較の「改善前 (baseline)」イメージを焼くためのブランチを作り直す。
#
# 現在のブランチの内容（トレース計装・compose・migrations を含む）をベースに、
# 性能改善コミットが触れたアプリコードだけを改善前の状態へ戻す。
# こうすることで「計装はあるが遅いアプリ」が得られ、モニタリングスイート上で
# 改善後と同じ形のトレースを比較できる。
#
# 戻す対象（性能改善コミット: 79b6cc6, 021d245 が触れたファイル）:
#   internal/handler/batch.go     … 一括ロード用ヘルパ。当時は存在しないため削除
#   internal/handler/post.go
#   internal/handler/search.go
#   internal/handler/trending.go
#
# 使い方: ./scripts/make-baseline-branch.sh [ベースにするref]
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# 性能改善が入る直前のコミット（79b6cc6 "fix: batch load posts to remove list N+1" の親）
PRE_PERF_REF="${PRE_PERF_REF:-79b6cc6^}"
BRANCH="${BRANCH:-perf/baseline-app}"
SOURCE_REF="${1:-HEAD}"

REVERT_FILES=(
  app/backend/internal/handler/post.go
  app/backend/internal/handler/search.go
  app/backend/internal/handler/trending.go
)
DELETE_FILES=(
  app/backend/internal/handler/batch.go
)

if [ -n "$(git status --porcelain)" ]; then
  echo "作業ツリーに未コミットの変更があります。commit か stash をしてから実行してください。" >&2
  exit 1
fi

ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore() { git checkout --quiet "$ORIG_BRANCH"; }
trap restore EXIT

git checkout --quiet -B "$BRANCH" "$SOURCE_REF"

git checkout "$PRE_PERF_REF" -- "${REVERT_FILES[@]}"
for f in "${DELETE_FILES[@]}"; do
  [ -e "$f" ] && git rm --quiet "$f"
done

git commit --quiet -m "[perf-compare] 性能比較用: アプリコードを性能改善前($(git rev-parse --short "$PRE_PERF_REF"))へ戻す

トレース計装 (internal/telemetry, otelhttp) と compose/migrations は
現在のものを保持したまま、一覧APIのN+1解消と集計テーブル利用を
取り消したイメージを焼くためのブランチ。
コンテナレジストリの :baseline タグとして push される。"

echo "==> ブランチ ${BRANCH} を $(git rev-parse --short "$SOURCE_REF") から作成しました ($(git rev-parse --short "$BRANCH"))"
