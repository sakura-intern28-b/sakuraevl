# 性能改善前後の比較手順（イメージのタグ切り替え）

モニタリングスイートに溜めたトレースを使って「性能改善前」と「改善後」の
エンドポイント応答時間を比較するための手順。

api コンテナのイメージタグだけを差し替えるので、db / proxy / frontend は
動かしたまま数秒で切り替えられる。

## 1. 何を比較しているのか

性能改善は次の4コミットで入っている。

| コミット | 内容 | 効く場所 |
|---|---|---|
| `79b6cc6` fix: batch load posts to remove list N+1 | 一覧APIのN+1解消（`batch.go` 追加） | アプリ |
| `de9d39c` perf: add recommended feed indexes | `002_recommended_indexes.sql` | DB |
| `021d245` perf: materialize recommended feed | `003_recommended_feed.sql` + `post.go` | DB + アプリ |
| `5df74f5` perf: preaggregate recent likes | `004_preaggregate_recommended_likes.sql` | DB |

このうち **アプリ側の差分（`batch.go` / `post.go` / `search.go` / `trending.go`）**
をイメージで焼き分けている。トレースは `otelhttp` によるHTTPサーバスパン
なので、N+1解消の効果がエンドポイントの応答時間としてそのまま出る。

> **なぜ当時のコミットをそのまま焼かないのか**
> 改善前のコミットには `internal/telemetry` も `otelhttp` も無く、
> そのままイメージにしてもトレースが1件も送信されない。
> そのため「現在のトレース計装 + 当時のアプリコード」という組み合わせで
> baseline イメージを作っている（`scripts/make-baseline-branch.sh`）。

## 2. タグ設計

| タグ | 中身 |
|---|---|
| `baseline` | 改善前のアプリコード（+ 現在のトレース計装） |
| `optimized` | 改善後のアプリコード。`main` への push で自動更新される |
| `latest` | `optimized` と同じもの（従来どおり） |
| `sha-<短縮SHA>` | `main` の各コミット。あとから特定の時点を呼び戻す用 |
| `baseline-<短縮SHA>` / `optimized-<短縮SHA>` | 焼いた時点を固定したい場合用 |

## 3. イメージを焼く

### 3-1. baseline ブランチを作る

```bash
cd app/backend
./scripts/make-baseline-branch.sh
```

`perf/baseline-app` ブランチが（作り直しも含めて）生成される。

### 3-2a. ローカルから push する場合

```bash
docker login intern28-b.sakuracr.jp
cd app/backend
REGISTRY_URL=intern28-b.sakuracr.jp ./scripts/build-variants.sh
```

`baseline` と `optimized` の両方が push される。片方だけなら
`./scripts/build-variants.sh baseline` のように指定する。

### 3-2b. GitHub Actions から push する場合

`perf/baseline-app` を push したうえで、Actions の **Auto Push** ワークフローを
手動実行（`workflow_dispatch`）する。

- `ref`: `perf/baseline-app`
- `image_tag`: `baseline`

`optimized` / `latest` / `sha-xxxxxxx` は `main` への push で自動的に作られる。

## 4. 切り替えて比較する

```bash
cd app/backend            # デプロイ先VMなら /opt/app

./scripts/switch-variant.sh baseline     # 改善前に切り替え
./scripts/switch-variant.sh optimized    # 改善後に切り替え
./scripts/switch-variant.sh status       # いま動いているタグの確認
```

- 選択したタグは `.env.variant` に保存される。`terraform apply` が `.env` を
  再生成しても消えない。
- `compose.reg.direct.yml` を使っている場合は
  `COMPOSE_FILE=compose.reg.direct.yml ./scripts/switch-variant.sh baseline`。

計測の流れ:

1. `baseline` に切り替え → 数分間、負荷（画面操作や `ab` / `hey` 等）をかける
2. `optimized` に切り替え → **同じ負荷を同じ時間** かける
3. モニタリングスイートで比較する

## 5. モニタリングスイートでの見分け方

どのイメージのトレースかは、リソース属性 `service.version` に入っている
（compose が `OTEL_RESOURCE_ATTRIBUTES=service.version=${BACKEND_TAG}` を渡す）。

- `service.name` は `sakuravel-api` のまま両者で共通
- `service.version` が `baseline` / `optimized`

TraceQL 例:

```
{ resource.service.version = "baseline"  && span.http.route = "GET /posts" }
{ resource.service.version = "optimized" && span.http.route = "GET /posts" }
```

`http.route`（例 `GET /posts`, `GET /trending`）ごとに p50 / p95 を並べると
改善幅が読み取れる。

## 6. 注意: DB側の改善はアプリを戻しても残る

`migrations/002〜004` で追加したインデックス・集計テーブルは
DBに残ったままなので、`baseline` に切り替えても「当時そのままの遅さ」には
ならない。アプリ側のN+1解消ぶんの差が見える、という比較になる。

### DBも含めて当時の状態で測りたい場合

`compose.baseline-db.yml` のような上書きファイルを用意し、`001_init.sql` だけを
流すようにしてボリュームごと作り直す。**データは消える**。

```yaml
# compose.baseline-db.yml
services:
  db:
    volumes:
      - ./migrations/001_init.sql:/docker-entrypoint-initdb.d/001_init.sql:ro
      - mariadb_data:/var/lib/mysql
```

```bash
cd app/backend
docker compose -f compose.reg.yml down --volumes
docker compose -f compose.reg.yml -f compose.baseline-db.yml up -d
./scripts/switch-variant.sh baseline
# seed/ のダミーデータを投入してから計測する
```

計測後は `down --volumes` してから通常の `compose.reg.yml` で起動し直すと、
`002〜004` を含む本来のスキーマに戻る。
