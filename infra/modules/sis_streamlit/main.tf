terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

resource "snowflake_stage" "streamlit" {
  database = var.database
  schema   = var.schema
  name     = var.stage_name
  comment  = var.comment
}

# SPCS版を使う場合には必須
resource "snowflake_compute_pool" "streamlit" {
  name                = var.compute_pool_name
  min_nodes           = var.min_nodes
  max_nodes           = var.max_nodes
  instance_family     = "CPU_X64_XS"
  auto_resume         = "true"
  initially_suspended = "true"
  auto_suspend_secs   = var.auto_suspend_secs
  comment             = var.comment
}

# SPCS版を使う場合には必須
resource "snowflake_execute" "external_access_integration" {
  execute = "CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION ${var.external_access_integration_name} ALLOWED_NETWORK_RULES = (snowflake.external_access.pypi_rule) ENABLED = TRUE"
  revert  = "DROP EXTERNAL ACCESS INTEGRATION IF EXISTS ${var.external_access_integration_name}"
}
