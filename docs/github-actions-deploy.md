# GitHub Actions からの Streamlit デプロイ

## 前提

| 項目 | 説明 |
|---|---|
| GitHub Actions Secrets | `SNOWFLAKE_PRIVATE_KEY`, `SNOWFLAKE_USER`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_ROLE` が登録済み |
| ローカル `.env` | CI上では存在しない。スクリプトは `.env` が無くても動作する（環境変数が直接セットされていればよい） |
| 認証方式 | キーペア認証 (`SNOWFLAKE_JWT`) |

## ポイント

### 1. `SNOWFLAKE_PRIVATE_KEY_RAW` を使う

`snow` CLI は `SNOWFLAKE_PRIVATE_KEY_RAW` 環境変数をサポートしている。
ローカルでは `SNOWFLAKE_PRIVATE_KEY_PATH`（ファイルパス）で認証しているが、
CI上ではファイルを書き出す必要はなく、Secretの値をそのまま `SNOWFLAKE_PRIVATE_KEY_RAW` にセットすればよい。

参考: https://docs.snowflake.com/developer-guide/snowflake-cli/connecting/configure-connections

### 2. 環境変数のマッピング

| GitHub Secrets | スクリプトが期待する環境変数 | 備考 |
|---|---|---|
| `SNOWFLAKE_PRIVATE_KEY` | `SNOWFLAKE_PRIVATE_KEY_RAW` | snow CLIが自動認識 |
| `SNOWFLAKE_USER` | `SNOWFLAKE_USER` | そのまま利用可能 |
| `SNOWFLAKE_DATABASE` | `SNOWFLAKE_DATABASE` | そのまま利用可能 |
| `SNOWFLAKE_ROLE` | `SNOWFLAKE_ROLE` | snow CLI の `--role` に渡される |
| (固定値) | `SNOWFLAKE_ORGANIZATION_NAME` | Secretsに追加するか、ワークフロー内で直接指定 |
| (固定値) | `SNOWFLAKE_ACCOUNT_NAME` | 同上 |
| (固定値) | `SNOWFLAKE_AUTHENTICATOR` | `SNOWFLAKE_JWT` を指定 |

### 3. スクリプトの `.env` 読み込みについて

`upload_streamlit_wh.sh` / `upload_streamlit_spcs.sh` は `.env` が存在すれば読み込むが、存在しなければスキップする（`if [ -f ... ]`）。
CI上では `.env` を作成せず、GitHub Actions の `env:` で直接環境変数をセットすればよい。

## デプロイ戦略

### アプリディレクトリの判定基準

`streamlit/apps/` 配下で以下のいずれかを含むディレクトリをアプリとみなす:

- `main.py`
- `app.py`
- `*_app.py` (例: `streamlit_app.py`, `dashboard_app.py`)

これらはStreamlitの `MAIN_FILE` として使われるエントリポイントファイルである。
入れ子構造にも対応しており、任意の深さのサブディレクトリがアプリになりうる。

```
streamlit/apps/
├── app1/streamlit_app.py          → アプリ: apps/app1
├── analytics/
│   ├── dashboard/app.py           → アプリ: apps/analytics/dashboard
│   └── report/main.py             → アプリ: apps/analytics/report
├── utils/helper.py                → 該当なし → アプリではない
└── shared_config.yml              → アプリではない
```

### トリガー条件

| 変更対象 | デプロイ対象 |
|---|---|
| アプリディレクトリ内のファイル | そのアプリのみデプロイ |
| `streamlit/common/**` | **全アプリ**をデプロイ |
| `scripts/upload_streamlit.sh` | **全アプリ**をデプロイ |

### アプリの追加方法

`streamlit/apps/` 配下に `main.py`、`app.py`、または `*_app.py` を含むディレクトリを作るだけ。ワークフローの変更は不要。

### 使用する GitHub Actions

| Action | 用途 |
|---|---|
| [tj-actions/changed-files@v46](https://github.com/tj-actions/changed-files) | 変更ファイルの検出 |
| [snowflakedb/snowflake-cli-action@v1.5](https://github.com/snowflakedb/snowflake-cli-action) | `snow` CLI のインストール |

## ワークフロー例

```yaml
name: Deploy Streamlit to Snowflake
on:
  push:
    branches: [main]
    paths:
      - "streamlit/apps/**"
      - "streamlit/common/**"
      - "scripts/upload_streamlit_wh.sh"
      - "scripts/upload_streamlit_spcs.sh"

jobs:
  # -------------------------------------------------------
  # 1. アプリ一覧の探索 (main.py or *_app.py を含むディレクトリ = アプリ)
  # -------------------------------------------------------
  discover:
    runs-on: ubuntu-latest
    outputs:
      all_apps: ${{ steps.discover.outputs.all_apps }}
    steps:
      - uses: actions/checkout@v4

      - name: Discover app directories
        id: discover
        run: |
          # main.py, app.py, または *_app.py を含むディレクトリをアプリとみなす
          APPS=$(find streamlit/apps \( -name 'main.py' -o -name 'app.py' -o -name '*_app.py' \) -exec dirname {} \; \
            | sort -u \
            | sed 's|^streamlit/||' \
            | jq -R -s -c 'split("\n") | map(select(length > 0))')
          echo "all_apps=${APPS}" >> "$GITHUB_OUTPUT"
          echo "Discovered apps: ${APPS}"

  # -------------------------------------------------------
  # 2. 変更検知
  # -------------------------------------------------------
  changes:
    runs-on: ubuntu-latest
    outputs:
      changed_files: ${{ steps.app-changes.outputs.all_changed_files }}
      common_changed: ${{ steps.common-changes.outputs.any_changed }}
      script_changed: ${{ steps.script-changes.outputs.any_changed }}
    steps:
      - uses: actions/checkout@v4

      - name: Detect changed files in apps/
        id: app-changes
        uses: tj-actions/changed-files@v46
        with:
          files: streamlit/apps/**
          json: "true"

      - name: Detect common changes
        id: common-changes
        uses: tj-actions/changed-files@v46
        with:
          files: streamlit/common/**

      - name: Detect script changes
        id: script-changes
        uses: tj-actions/changed-files@v46
        with:
          files: |
            scripts/upload_streamlit_wh.sh
            scripts/upload_streamlit_spcs.sh

  # -------------------------------------------------------
  # 3. デプロイ対象の決定
  #    discover の結果と変更ファイルを突合して対象アプリを特定
  # -------------------------------------------------------
  resolve:
    needs: [discover, changes]
    runs-on: ubuntu-latest
    outputs:
      targets: ${{ steps.resolve.outputs.targets }}
    steps:
      - name: Resolve deploy targets
        id: resolve
        run: |
          ALL_APPS='${{ needs.discover.outputs.all_apps }}'

          if [ "${{ needs.changes.outputs.common_changed }}" = "true" ] || \
             [ "${{ needs.changes.outputs.script_changed }}" = "true" ]; then
            # common/ またはスクリプト変更 → 全アプリをデプロイ
            echo "targets=${ALL_APPS}" >> "$GITHUB_OUTPUT"
          else
            # 変更ファイルが属するアプリだけを抽出
            CHANGED='${{ needs.changes.outputs.changed_files }}'
            TARGETS=$(jq -n -c \
              --argjson apps "$ALL_APPS" \
              --argjson files "$CHANGED" \
              '[
                $apps[] |
                . as $app |
                select($files | any(startswith("streamlit/" + $app + "/")))
              ]')
            echo "targets=${TARGETS}" >> "$GITHUB_OUTPUT"
          fi

  # -------------------------------------------------------
  # 4. デプロイ実行 (matrix で並列)
  # -------------------------------------------------------
  deploy:
    needs: resolve
    if: needs.resolve.outputs.targets != '[]'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        app: ${{ fromJson(needs.resolve.outputs.targets) }}
    steps:
      - uses: actions/checkout@v4

      - uses: snowflakedb/snowflake-cli-action@v1.5

      - name: Deploy ${{ matrix.app }}
        env:
          SNOWFLAKE_AUTHENTICATOR: SNOWFLAKE_JWT
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_ORGANIZATION_NAME: <YOUR_ORG_NAME>
          SNOWFLAKE_ACCOUNT_NAME: <YOUR_ACCOUNT_NAME>
          SNOWFLAKE_PRIVATE_KEY_RAW: ${{ secrets.SNOWFLAKE_PRIVATE_KEY }}
          SNOWFLAKE_DATABASE: ${{ secrets.SNOWFLAKE_DATABASE }}
          SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
        run: |
          bash scripts/upload_streamlit_wh.sh ${{ matrix.app }}
```

## 注意事項

- `SNOWFLAKE_PRIVATE_KEY` (Secrets) → `SNOWFLAKE_PRIVATE_KEY_RAW` (env) への名前変換が必要
- `SNOWFLAKE_ORGANIZATION_NAME` と `SNOWFLAKE_ACCOUNT_NAME` は Secrets に追加するか、ワークフロー内にハードコードするか検討すること
- `SNOWFLAKE_ROLE` は Secrets で管理し、環境ごとに適切なロールを設定すること
- アプリ追加は `streamlit/apps/` 配下に `main.py` または `*_app.py` を含むディレクトリを作るだけ。ワークフローの変更は不要
