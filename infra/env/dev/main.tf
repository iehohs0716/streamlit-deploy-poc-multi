locals {
  env                = "dev"
  project_name_kebab = var.project_name
}

resource "snowflake_schema" "app" {
  database = var.snowflake_database
  name     = "STREAMLIT_APP_SIS_MULTI"
  comment  = "Schema for Streamlit apps (${local.env})"
}

module "sis_streamlit" {
  source = "../../modules/sis_streamlit"

  database                         = var.snowflake_database
  schema                           = snowflake_schema.app.name
  stage_name                       = "STREAMLIT_STAGE_MULTI"
  compute_pool_name                = "STREAMLIT_POOL_MULTI"
  external_access_integration_name = "MART_CHECK_APP_SIS_PYPI_EAI"
  comment                          = "Managed by Terraform (${local.env})"
}
