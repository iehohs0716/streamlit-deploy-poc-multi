"""Snowflake接続ユーティリティ
"""

from __future__ import annotations

from functools import lru_cache
from typing import TYPE_CHECKING

import streamlit as st
from jinja2 import Environment, FileSystemLoader

if TYPE_CHECKING:
    from snowflake.snowpark import Session


@lru_cache(maxsize=1)
def get_session() -> Session:
    """Snowparkセッションを取得する.(ローカル&SiSのどちらも利用可能)"""

    return st.connection("snowflake")

def render_query(template_name: str, *, template_dir: str, **kwargs: object) -> str:
    """Jinja2テンプレートからSQLをレンダリングする."""
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template(template_name)
    return template.render(**kwargs)


def execute_query(sql: str):
    """SQLクエリを実行し、DataFrameとして返す."""
    conn = get_session()
    return conn.query(sql, ttl=600)
