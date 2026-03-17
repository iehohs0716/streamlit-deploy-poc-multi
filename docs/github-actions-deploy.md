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

| 変更対象 | デプロイ対象 | 例 |
|---|---|---|
| アプリディレクトリ内のファイル | そのアプリのみ | `apps/app1/main.py` → `apps/app1` |
| `streamlit/common/<app_dir>/**` | 対応するアプリのみ | `common/app1/utils.py` → `apps/app1` |
| `streamlit/common/<parent_dir>/*` | 配下の全アプリ | `common/analytics/shared.py` → `apps/analytics/dashboard`, `apps/analytics/report` |
| `streamlit/common/*` (直下) | **全アプリ** | `common/base.py` → 全アプリ |
| `scripts/upload_streamlit_*.sh` | **全アプリ** | — |

### ランタイムの選択

各アプリディレクトリに `runtime.conf` を置くことで、デプロイ先のランタイムを指定できる。

| `runtime.conf` の中身 | デプロイスクリプト | 説明 |
|---|---|---|
| `wh` | `upload_streamlit_wh.sh` | Warehouse ランタイム |
| `spcs` | `upload_streamlit_spcs.sh` | Container ランタイム (SPCS) |
| (ファイルなし) | `upload_streamlit_wh.sh` | デフォルトは `wh` |

### アプリの追加方法

`streamlit/apps/` 配下に `main.py`、`app.py`、または `*_app.py` を含むディレクトリを作るだけ。ワークフローの変更は不要。
SPCS を使う場合は `runtime.conf` に `spcs` と記載する。

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
  # 1. アプリ一覧の探索
  #    - main.py / app.py / *_app.py を含むディレクトリ = アプリ
  #    - 各アプリの runtime.conf でランタイムを判定 (wh or spcs)
  #      例: streamlit/apps/app1/runtime.conf に "spcs" と書けば SPCS 版でデプロイ
  #      ファイルがなければデフォルト wh
  #    - 出力形式: [{"app":"apps/app1","runtime":"wh"}, ...]
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
          # runtime.conf があれば読み取り、なければデフォルト wh
          APPS=$(find streamlit/apps \( -name 'main.py' -o -name 'app.py' -o -name '*_app.py' \) -exec dirname {} \; \
            | sort -u \
            | while read -r dir; do
                app_path=$(echo "$dir" | sed 's|^streamlit/||')
                if [ -f "$dir/runtime.conf" ]; then
                  runtime=$(tr -d '[:space:]' < "$dir/runtime.conf")
                else
                  runtime="wh"
                fi
                if [ "$runtime" != "wh" ] && [ "$runtime" != "spcs" ]; then
                  echo "ERROR: Invalid runtime '$runtime' in $dir/runtime.conf. Must be 'wh' or 'spcs'." >&2
                  exit 1
                fi
                echo "{\"app\":\"${app_path}\",\"runtime\":\"${runtime}\"}"
              done \
            | jq -s -c '.')
          echo "all_apps=${APPS}" >> "$GITHUB_OUTPUT"
          echo "Discovered apps: ${APPS}"

  # -------------------------------------------------------
  # 2. 変更検知
  # -------------------------------------------------------
  changes:
    runs-on: ubuntu-latest
    outputs:
      changed_files: ${{ steps.app-changes.outputs.all_changed_files }}
      common_changed_files: ${{ steps.common-changes.outputs.all_changed_files }}
      script_changed: ${{ steps.script-changes.outputs.any_changed }}
    steps:
      - uses: actions/checkout@v4

      - name: Detect changed files in apps/
        id: app-changes
        uses: tj-actions/changed-files@v46
        with:
          files: streamlit/apps/**
          json: "true"

      - name: Detect changed files in common/
        id: common-changes
        uses: tj-actions/changed-files@v46
        with:
          files: streamlit/common/**
          json: "true"

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

          if [ "${{ needs.changes.outputs.script_changed }}" = "true" ]; then
            # スクリプト変更 → 全アプリをデプロイ
            echo "targets=${ALL_APPS}" >> "$GITHUB_OUTPUT"
            exit 0
          fi

          # apps/ の変更から対象アプリを抽出
          APP_CHANGED='${{ needs.changes.outputs.changed_files }}'
          APP_TARGETS=$(jq -n -c \
            --argjson apps "$ALL_APPS" \
            --argjson files "$APP_CHANGED" \
            '[
              $apps[] |
              select($files | any(startswith("streamlit/" + .app + "/")))
            ]')

          # common/ の変更からサブディレクトリを見て対応アプリを抽出
          COMMON_CHANGED='${{ needs.changes.outputs.common_changed_files }}'
          COMMON_TARGETS=$(jq -n -c \
            --argjson apps "$ALL_APPS" \
            --argjson files "$COMMON_CHANGED" \
            '[
              $apps[] |
              (.app | ltrimstr("apps/")) as $app_rel |
              select(
                $files | any(
                  ltrimstr("streamlit/common/") |
                  split("/") | .[:-1] | join("/") |
                  . as $dir |
                  ($dir == "") or
                  (($dir + "/") | startswith($app_rel + "/")) or
                  (($app_rel + "/") | startswith($dir + "/"))
                )
              )
            ] | unique_by(.app)')

          # 2つのリストをマージして重複排除
          TARGETS=$(jq -n -c \
            --argjson a "$APP_TARGETS" \
            --argjson b "$COMMON_TARGETS" \
            '($a + $b) | unique_by(.app)')
          echo "targets=${TARGETS}" >> "$GITHUB_OUTPUT"

  # -------------------------------------------------------
  # 4. デプロイ実行 (matrix で並列)
  #    matrix.include に [{app, runtime}, ...] が展開され、
  #    runtime の値で upload_streamlit_wh.sh / upload_streamlit_spcs.sh を切り替え
  # -------------------------------------------------------
  deploy:
    needs: resolve
    if: needs.resolve.outputs.targets != '[]'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include: ${{ fromJson(needs.resolve.outputs.targets) }}
    steps:
      - uses: actions/checkout@v4

      - uses: snowflakedb/snowflake-cli-action@v1.5

      - name: Deploy ${{ matrix.app }} (${{ matrix.runtime }})
        env:
          SNOWFLAKE_AUTHENTICATOR: SNOWFLAKE_JWT
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_ORGANIZATION_NAME: <YOUR_ORG_NAME>
          SNOWFLAKE_ACCOUNT_NAME: <YOUR_ACCOUNT_NAME>
          SNOWFLAKE_PRIVATE_KEY_RAW: ${{ secrets.SNOWFLAKE_PRIVATE_KEY }}
          SNOWFLAKE_DATABASE: ${{ secrets.SNOWFLAKE_DATABASE }}
          SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
        run: |
          bash scripts/upload_streamlit_${{ matrix.runtime }}.sh ${{ matrix.app }}
```

## 注意事項

- `SNOWFLAKE_PRIVATE_KEY` (Secrets) → `SNOWFLAKE_PRIVATE_KEY_RAW` (env) への名前変換が必要
- `SNOWFLAKE_ORGANIZATION_NAME` と `SNOWFLAKE_ACCOUNT_NAME` は Secrets に追加するか、ワークフロー内にハードコードするか検討すること
- `SNOWFLAKE_ROLE` は Secrets で管理し、環境ごとに適切なロールを設定すること
- アプリ追加は `streamlit/apps/` 配下に `main.py` または `*_app.py` を含むディレクトリを作るだけ。ワークフローの変更は不要
- SPCS を使うアプリは `runtime.conf` に `spcs` と記載する。省略時は `wh`（Warehouse）がデフォルト
