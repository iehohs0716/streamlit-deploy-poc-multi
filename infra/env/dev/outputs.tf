output "stage_fully_qualified_name" {
  description = "Fully qualified name of the Streamlit stage"
  value       = module.sis_streamlit.stage_fully_qualified_name
}

output "compute_pool_name" {
  description = "Name of the compute pool"
  value       = module.sis_streamlit.compute_pool_name
}
