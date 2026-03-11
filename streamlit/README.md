# streamlit-deploy-poc-multi / streamlit

Streamlit in Snowflake (SiS) マルチページ構成デプロイの PoC。

## ディレクトリ構成

```
streamlit/
├── .streamlit/
│   ├── secrets.toml               # Snowflake 認証情報（git 管理外）
│   └── secrets.toml.sample        # 認証情報テンプレート
├── apps/
│   └── app1/
│       ├── streamlit_app.py       # Streamlit エントリーポイント
│       └── queries/               # SQL テンプレート（Jinja2）
├── common/
│   ├── __init__.py
│   └── utils.py                   # 共通ユーティリティ
├── environment.yml                # SiS デプロイ用の依存定義
├── snowflake.yml                  # SiS アプリ定義（Snowflake CLI）
├── pyproject.toml                 # ローカル開発用（uv 管理）
└── requirements.txt
```

## セットアップ

### 1. 認証情報の準備

`.streamlit/secrets.toml.sample` をコピーして実際の値を設定する。

```bash
cp .streamlit/secrets.toml.sample .streamlit/secrets.toml
```

```toml
[connections.snowflake]
account = "YOUR_ORG-YOUR_ACCOUNT"
user = "YOUR_USER"
private_key_file = "/path/to/your.p8"
warehouse = "YOUR_WH"
database = "YOUR_DB"
schema = "YOUR_SCHEMA"
```

> `secrets.toml` は `.gitignore` で除外済み。

### 2. 依存関係のインストール

```bash
uv sync
```

### 3. ローカル起動（例）

```bash
uv run streamlit run apps/app1/streamlit_app.py
```

### 4. SiS へのデプロイ

```bash
snow streamlit deploy
```
