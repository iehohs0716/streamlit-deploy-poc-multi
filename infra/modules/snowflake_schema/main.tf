terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

resource "snowflake_schema" "this" {
  database = var.database
  name     = var.name
  comment  = var.comment
}
