#!/bin/bash
set -euo pipefail

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

DATABASE="${SNOWFLAKE_DATABASE:?SNOWFLAKE_DATABASE is not set}"
SCHEMA="STREAMLIT_APP_SIS_MULTI"
STAGE="${DATABASE}.${SCHEMA}.STREAMLIT_STAGE_MULTI"
STREAMLIT_NAME="${DATABASE}.${SCHEMA}.MART_CHECK_APP_SIS"
COMPUTE_POOL="STREAMLIT_POOL_MULTI"
WAREHOUSE="COMPUTE_WH"
RUNTIME="SYSTEM\$ST_CONTAINER_RUNTIME_PY3_11"
EAI="MART_CHECK_APP_SIS_PYPI_EAI"

APP_ROOT="${1:?Usage: $0 <app_path> (e.g. apps/app1)}"

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
  MAIN_FILE = 'streamlit_app.py'
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
