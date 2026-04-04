"""Snowflake接続ユーティリティ
"""

from __future__ import annotations

import inspect
import os
from typing import TYPE_CHECKING

import streamlit as st
from jinja2 import Environment, FileSystemLoader

if TYPE_CHECKING:
    import pandas as pd
    from snowflake.snowpark import Session


@st.cache_resource
def get_active_session() -> Session:
    """Snowparkセッションを取得する.(ローカル&SiSのどちらも利用可能)"""

    return st.connection("snowflake").session()

# conn.queryを使うことでキャッシュが適用されるため、アノテーションは不要
def execute_query(sql: str) -> pd.DataFrame:
    """SQLクエリを実行し、Pandas DataFrameとして返す."""
    conn = st.connection("snowflake")
    return conn.query(sql, ttl=600)

@st.cache_data
def _get_queries_dir(caller_file: str) -> str:
    """呼び出し元ファイルの隣にある queries ディレクトリのパスを返す."""
    return os.path.join(os.path.dirname(caller_file), "queries")
  
@st.cache_data
def _render_query_cached(template_name: str, template_dir: str, kwargs_items: tuple) -> str:
    kwargs = dict(kwargs_items)
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template(template_name)
    return template.render(**kwargs)

def render_query(template_name: str, **kwargs: object) -> str:
    """Jinja2テンプレートからSQLをレンダリングする.

    呼び出し元ファイルと同階層の queries/ ディレクトリからテンプレートを読み込む.
    """
    caller_file = inspect.stack()[1].filename
    template_dir = _get_queries_dir(caller_file)
    return _render_query_cached(template_name, template_dir, tuple(sorted(kwargs.items())))

