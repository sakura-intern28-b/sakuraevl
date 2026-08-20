# 28卒エンジニアインターン用インフラ

Terraform だけで構築します (シェルスクリプトは不要)。

## 1. 秘密情報を1ファイルにまとめる

```
cd infra/terraform
cp secret.auto.tfvars.example secret.auto.tfvars
```

クレデンシャルなどは1Passwordに入ってます。
`tfstate_bucket_name` には**アカウント・環境ごとに一意な**バケット名を書きます
(バケットは次の手順で Terraform が自動作成します)。

`secret.auto.tfvars` はファイル名が `.auto.tfvars` なので、そのディレクトリで
`terraform` を実行すると自動で読み込まれます (環境変数の設定は不要)。
state用バケットを作る `infra/tfstate` にも同名のファイルがあります (次項)。

## 2. state 用バケットを作る (初回のみ)

Terraform の `backend` ブロックには変数を書けません。
そのため「バケットとアクセスキーを作るだけ」の小さな構成 `infra/tfstate` を先に流し、
その出力から本体構成の backend 設定 (`infra/terraform/backend_override.tf`) を自動生成します。

```
cd infra/tfstate
cp secret.auto.tfvars.example secret.auto.tfvars   # トークンとバケット名を書く
terraform init
terraform apply
```

`infra/tfstate/secret.auto.tfvars` に書くのは3つ (APIトークン、シークレット、バケット名) だけです。
秘密情報を2ファイルに分けたくない場合は、このファイルを作らずに
`terraform apply -var-file=../terraform/secret.auto.tfvars -compact-warnings` でも構いません
(この構成が使わない変数について「Value for undeclared variable」警告が出ますが無害です)。

これで以下が作られます。

- Object Storage バケット (state 保存先、バージョニング有効)
- そのバケットに読み書きできるパーミッション (アクセスキー / シークレット)
- `infra/terraform/backend_override.tf` (上記の値を埋めた backend 設定、git管理外)

この構成自身の state だけはローカル (`infra/tfstate/terraform.tfstate`) に置きます
(バケットを作る前に、そのバケットへ state は置けないため)。

### 既にあるバケットを使う場合 (2人目以降)

作成ではなく import します。

```
cd infra/tfstate
cp secret.auto.tfvars.example secret.auto.tfvars   # 既存バケット名を書く
terraform init
terraform import sakura_object_storage_bucket.tfstate tky01/<バケット名>
terraform apply
```

## 3. 本体を構築する

```
cd infra/terraform
terraform init
terraform apply
```

`backend_override.tf` が backend ブロックを丸ごと上書きするので、
`-backend-config` も環境変数 (`AWS_ACCESS_KEY_ID` など) も指定不要です。

SSH 鍵は `secret.auto.tfvars` の `server_ssh_public_key_path` で指定します
(秘密鍵は同じパスから `.pub` を除いたもの)。手元に無ければ先に作ってください。

```
ssh-keygen -t ed25519 -f ~/.ssh/sakuravel_ed25519
```

## モニタリングスイート

ログ / メトリック / トレースの3ストレージと送信用アクセスキーは
`infra/terraform/monitoring_suite.tf` が作成し、その値が cloud-init の
sacloud-otel-collector 設定へ直接流し込まれます。
コンパネで発行したエンドポイントIDやトークンを `secret.auto.tfvars` に
書き写す旧方式は廃止しました。

保持期間は変数で変えられます (既定: ログ30日 / トレース14日。
メトリックはプロバイダーが保持期間の指定に未対応)。

```
monitoring_logs_retention_days   = 30
monitoring_traces_retention_days = 14
monitoring_suite_name_prefix     = "sakuraevl"
```

**注意**: cloud-init (user_data) はVMの初回起動時にしか実行されません。
ストレージを作り直して endpoint/token が変わっても apply はサーバーを
in-place 更新するだけで Collector の設定は古いままです。反映するには
`terraform apply -replace=sakura_disk.docker_host -replace=sakura_server.docker_host`
でVMを作り直してください。

## トラブルシューティング

- `No valid credential sources found` /
  `no EC2 IMDS role found`
  → backend にアクセスキーが渡っていません。`infra/terraform/backend_override.tf` が
  存在するか確認し、無ければ手順2をやり直してください。
- `InvalidAccessKeyId` / `403 Forbidden`
  → コントロールパネル側でパーミッション(アクセスキー)が削除されている可能性があります。
  `terraform -chdir=infra/tfstate state rm sakura_object_storage_permission.tfstate` の後に
  手順2の apply をやり直すとキーが再発行され、`backend_override.tf` も更新されます。
  その後 `terraform -chdir=infra/terraform init -reconfigure` を実行してください。
- init 時に `Do you want to copy existing state to the new backend?` と聞かれた場合
  → **no** と答えてください (`infra/terraform/terraform.tfstate` はリモートへ移行済みの
  空の残骸で、コピーするとバケット上の state を空で上書きしてしまいます)。
- `Backend initialization required` / `A change in the backend configuration has been detected`
  → `terraform init -reconfigure` を実行してください。
