"""サンプルアプリ"""

from __future__ import annotations

import streamlit as st

from common.utils import get_active_session, render_query, execute_query

session = get_active_session() # snowflake.snowpark.context.get_active_session()で定義していたものをそのまま利用可能

# --- ページ設定 ---
st.set_page_config(
    page_title=" サンプルアプリ",
    page_icon=":shark:",
    layout="wide",
)

# --- タイトル ---
st.title("サンプルアプリ")

# --- キックオフセレクタ ---
# 選択メニューとテキストフィールドが横に並んだコンポーネント
col_select, col_text = st.columns(2)

# queries/account_list.sql.j2にある"all_info"CTEを参照して物理名を確認して選択項目を作る
SEARCH_OPTIONS = {
    "メールアドレス検索": "email",
    "氏名検索": "customer_name",
    "ID検索": "id",
    "電話番号": "phone",
    "生年月日検索": "birthday"
}

with col_select:
    search_type = st.selectbox(
        "検索種別",
        options=list(SEARCH_OPTIONS.keys()),
        index=0,
    )

with col_text:
    search_value = st.text_input(
        "検索値",
        value="",
        placeholder="検索値を入力してください",
    )

# --- クエリ発行 ---
# キックオフセレクタに入力があった時点でクエリが発行される
column_name = SEARCH_OPTIONS.get(search_type, "")

query = render_query(
    "test.sql.j2",
    column_name=column_name,
    search_value=search_value,
    limit=50,
)

with st.popover(":material/content_copy: SQL"):
    st.code(query, language="sql")

if not search_value:
    st.warning("検索値を入力してください")
    st.stop()

try:
    df = execute_query(query)
    st.dataframe(df, use_container_width=True)
    st.info(f"{len(df)} 件取得しました")
except Exception as e:
    st.error(f"クエリ実行エラー: {e}")
