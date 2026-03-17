variable "database" {
  description = "Snowflake database name"
  type        = string
}

variable "name" {
  description = "Schema name"
  type        = string
}

variable "comment" {
  description = "Comment for the schema"
  type        = string
  default     = null
}
