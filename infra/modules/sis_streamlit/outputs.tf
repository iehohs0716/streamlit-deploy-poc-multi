output "stage_fully_qualified_name" {
  description = "Fully qualified name of the stage"
  value       = snowflake_stage.streamlit.fully_qualified_name
}

output "compute_pool_name" {
  description = "Name of the compute pool"
  value       = snowflake_compute_pool.streamlit.name
}

output "external_access_integration_name" {
  description = "Name of the external access integration"
  value       = var.external_access_integration_name
}
