#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

run_test() {
  local test_name="$1"
  local all_apps="$2"
  local common_changed="$3"
  local expected="$4"

  actual=$(jq -n -c \
    --argjson apps "$all_apps" \
    --argjson files "$common_changed" \
    '[
      $apps[] |
      . as $app |
      ($app | ltrimstr("apps/")) as $app_rel |
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
    ] | unique')

  if [ "$actual" = "$expected" ]; then
    echo "PASS: ${test_name}"
    echo "  result: ${actual}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${test_name}"
    echo "  expected: ${expected}"
    echo "  actual:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

# --------------------------------------------------
# テスト1: app1 の common だけ変更 → app1 のみ対象
# --------------------------------------------------
run_test \
  "app1のcommonのみ変更" \
  '["apps/app1", "apps/analytics/dashboard"]' \
  '["streamlit/common/app1/utils.py"]' \
  '["apps/app1"]'

# --------------------------------------------------
# テスト2: 2つのアプリの common を変更 → 両方対象
# --------------------------------------------------
run_test \
  "app1とanalytics/dashboardのcommon変更" \
  '["apps/app1", "apps/analytics/dashboard"]' \
  '["streamlit/common/app1/utils.py", "streamlit/common/analytics/dashboard/helper.py"]' \
  '["apps/analytics/dashboard","apps/app1"]'

# --------------------------------------------------
# テスト3: どのアプリにもマッチしない common 変更 → 空配列
# --------------------------------------------------
run_test \
  "マッチしないcommon変更" \
  '["apps/app1", "apps/analytics/dashboard"]' \
  '["streamlit/common/unknown/config.py"]' \
  '[]'

# --------------------------------------------------
# テスト4: common の変更なし（空配列） → 空配列
# --------------------------------------------------
run_test \
  "common変更なし" \
  '["apps/app1", "apps/analytics/dashboard"]' \
  '[]' \
  '[]'

# --------------------------------------------------
# テスト5: 同じアプリに複数の common ファイル変更 → 重複排除
# --------------------------------------------------
run_test \
  "同一アプリに複数common変更（重複排除）" \
  '["apps/app1", "apps/analytics/dashboard"]' \
  '["streamlit/common/app1/utils.py", "streamlit/common/app1/config.py"]' \
  '["apps/app1"]'

# --------------------------------------------------
# テスト6: ネストしたアプリパスの完全一致マッチ
# --------------------------------------------------
run_test \
  "ネストしたアプリanalytics/reportのcommon変更" \
  '["apps/app1", "apps/analytics/dashboard", "apps/analytics/report"]' \
  '["streamlit/common/analytics/report/query.py"]' \
  '["apps/analytics/report"]'

# --------------------------------------------------
# テスト7: 親ディレクトリの変更 → 配下の全アプリに影響
#   common/analytics/shared.py が変更
#   → analytics/dashboard と analytics/report の両方がデプロイ対象
# --------------------------------------------------
run_test \
  "親ディレクトリの変更は配下の全アプリに影響" \
  '["apps/app1", "apps/analytics/dashboard", "apps/analytics/report"]' \
  '["streamlit/common/analytics/shared.py"]' \
  '["apps/analytics/dashboard","apps/analytics/report"]'

# --------------------------------------------------
# テスト8: common 直下のファイル変更 → 全アプリに影響
#   common/shared_util.py が変更
#   → 全アプリがデプロイ対象
# --------------------------------------------------
run_test \
  "common直下のファイル変更は全アプリに影響" \
  '["apps/app1", "apps/analytics/dashboard"]' \
  '["streamlit/common/shared_util.py"]' \
  '["apps/analytics/dashboard","apps/app1"]'

# --------------------------------------------------
# 結果サマリ
# --------------------------------------------------
echo ""
echo "=============================="
echo "PASS: ${PASS} / FAIL: ${FAIL}"
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
