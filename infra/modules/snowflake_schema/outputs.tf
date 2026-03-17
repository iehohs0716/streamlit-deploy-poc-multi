output "name" {
  description = "Name of the schema"
  value       = snowflake_schema.this.name
}

output "fully_qualified_name" {
  description = "Fully qualified name of the schema"
  value       = snowflake_schema.this.fully_qualified_name
}
