#!/bin/bash
set -euo pipefail

# 必須ツールのチェック関数
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "ERROR: $1 コマンドが見つかりません。" >&2
    echo "$2" >&2
    exit 1
  fi
}

# 依存ツールのチェック
check_command "snow" "Snowflake CLIをインストールしてください: https://sfc-repo.snowflakecomputing.com/snowflake-cli/index.html"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STREAMLIT_DIR="$SCRIPT_DIR/../streamlit"

# .envから環境変数を読み込む
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
fi

export SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ORGANIZATION_NAME}-${SNOWFLAKE_ACCOUNT_NAME}"
SNOWFLAKE_ROLE="${SNOWFLAKE_ROLE:?SNOWFLAKE_ROLEを.envに設定してください}"
SNOW_OPTS="--temporary-connection --account ${SNOWFLAKE_ACCOUNT} --user ${SNOWFLAKE_USER} --authenticator ${SNOWFLAKE_AUTHENTICATOR} --role ${SNOWFLAKE_ROLE}"

APP_ROOT="${1:?Usage: $0 <app_path> (e.g. apps/app1)}"

DATABASE="${SNOWFLAKE_DATABASE:?SNOWFLAKE_DATABASE is not set}"
SCHEMA="${SNOWFLAKE_SCHEMA}"
STAGE="${DATABASE}.${SCHEMA}.${SNOWFLAKE_STAGE}"
APP_PREFIX="${SNOWFLAKE_STREAMLIT_APP_PREFIX:-}"
STREAMLIT_NAME="${DATABASE}.${SCHEMA}.${APP_PREFIX}_$(echo "${APP_ROOT}" | sed 's/\//_/g' | tr '[:lower:]' '[:upper:]')"
WAREHOUSE="${SNOWFLAKE_WH}"
COMPUTE_POOL="${SNOWFLAKE_COMPUTE_POOL}"
RUNTIME="${SNOWFLAKE_RUNTIME}"
EAI="${SNOWFLAKE_EAI}"

# エントリポイントの自動検出 (main.py / app.py / *_app.py)
MAIN_FILES=$(find "${STREAMLIT_DIR}/${APP_ROOT}" -maxdepth 1 \( -name 'main.py' -o -name 'app.py' -o -name '*_app.py' \) -exec basename {} \;)
MAIN_FILE_COUNT=$(echo "$MAIN_FILES" | grep -c .)
if [ "$MAIN_FILE_COUNT" -eq 0 ]; then
  echo "ERROR: No entry point found in ${STREAMLIT_DIR}/${APP_ROOT}" >&2
  echo "  Expected one of: main.py, app.py, *_app.py" >&2
  exit 1
elif [ "$MAIN_FILE_COUNT" -gt 1 ]; then
  echo "ERROR: Multiple entry points found in ${STREAMLIT_DIR}/${APP_ROOT}:" >&2
  echo "$MAIN_FILES" | sed 's/^/  - /' >&2
  echo "  Each app directory must contain exactly one entry point." >&2
  exit 1
fi
MAIN_FILE="$MAIN_FILES"

echo "========================================="
echo "Streamlit Upload & Deploy (SPCS版)"
echo "========================================="
echo ""

echo "Deleting __pycache__ ..."
find "${STREAMLIT_DIR}/${APP_ROOT}" "${STREAMLIT_DIR}/common" -type d -name '__pycache__' -exec rm -rf {} +
echo ""

echo "Uploading ${APP_ROOT}/ ..."
snow stage copy "$STREAMLIT_DIR/${APP_ROOT}" "@${STAGE}/${APP_ROOT}" --recursive --overwrite $SNOW_OPTS
echo ""

echo "Uploading common/ ..."
snow stage copy "$STREAMLIT_DIR/common" "@${STAGE}/${APP_ROOT}/common" --recursive --overwrite $SNOW_OPTS
echo ""

echo "Uploading pyproject.toml ..."
snow stage copy "$STREAMLIT_DIR/pyproject.toml" "@${STAGE}/${APP_ROOT}" --overwrite $SNOW_OPTS
echo ""

echo "Creating Streamlit app (Container Runtime) ..."
snow sql -q "
CREATE OR REPLACE STREAMLIT ${STREAMLIT_NAME}
  FROM '@${STAGE}/${APP_ROOT}'
  MAIN_FILE = '${MAIN_FILE}'
  QUERY_WAREHOUSE = ${WAREHOUSE}
  RUNTIME_NAME = '${RUNTIME}'
  COMPUTE_POOL = ${COMPUTE_POOL}
  EXTERNAL_ACCESS_INTEGRATIONS = (${EAI})
  COMMENT = 'Managed by upload_streamlit.sh';
" $SNOW_OPTS
echo ""

echo "========================================="
echo "Deploy complete: ${STREAMLIT_NAME}"
echo "========================================="
