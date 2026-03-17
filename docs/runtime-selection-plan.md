# アプリごとの SPCS/WH ランタイム選択

## Context

現在のワークフローは全アプリを `upload_streamlit_wh.sh`（Warehouse版）で固定デプロイしている。
アプリごとに WH か SPCS かを選べるようにしたい。

## 方針: `runtime.conf` マーカーファイル

各アプリディレクトリに `runtime.conf` を置き、中身に `wh` または `spcs` と書く。
ファイルがなければデフォルトで `wh`。既存アプリは変更不要。

```
streamlit/apps/app1/
  streamlit_app.py
  runtime.conf          ← "wh" or "spcs"（省略可、デフォルト wh）
```

### 選定理由

- 中央設定ファイル方式だと、アプリ追加時に2箇所（ディレクトリ+設定ファイル）の変更が必要になり、「ディレクトリを作るだけ」のコンセプトが崩れる
- `environment.yml` / `pyproject.toml` での自動判別は、これらが `streamlit/` 直下の共有ファイルであるため使えない

## 変更箇所

### 1. `docs/github-actions-deploy.md` — discover ジョブ

`all_apps` の出力形式を文字列配列からオブジェクト配列に変更:

```
// Before: ["apps/app1", "apps/analytics/dashboard"]
// After:  [{"app":"apps/app1","runtime":"wh"}, {"app":"apps/analytics/dashboard","runtime":"spcs"}]
```

`find` の後に `runtime.conf` を読んでオブジェクトを組み立てる。不正な値はエラーで即停止。

### 2. `docs/github-actions-deploy.md` — resolve ジョブ

jq のフィルタを修正:
- `$apps[]` → `$apps[].app` でパス比較
- 出力は `{"app": ..., "runtime": ...}` のオブジェクト配列を維持

### 3. `docs/github-actions-deploy.md` — deploy ジョブ

```yaml
strategy:
  matrix:
    include: ${{ fromJson(needs.resolve.outputs.targets) }}
steps:
  - run: bash scripts/upload_streamlit_${{ matrix.runtime }}.sh ${{ matrix.app }}
```

スクリプト名が `upload_streamlit_wh.sh` / `upload_streamlit_spcs.sh` なので `${{ matrix.runtime }}` でそのまま切り替え可能。

### 4. `docs/github-actions-deploy.md` — ドキュメント説明部分

- 「アプリの追加方法」セクションに `runtime.conf` の説明を追加
- デフォルト動作（WH）の記述

### 5. `streamlit/apps/app1/runtime.conf`（任意）

既存アプリにサンプルとして追加。中身は `wh`。

## 変更不要なファイル

- `scripts/upload_streamlit_wh.sh` — そのまま
- `scripts/upload_streamlit_spcs.sh` — そのまま
- `infra/` — そのまま

## 検証方法

- discover の `find` + `runtime.conf` 読み取りロジックをローカルでシェル実行して JSON 出力を確認
- resolve の jq ロジックを `scripts/test_common_targets.sh` と同様のテストスクリプトで検証
