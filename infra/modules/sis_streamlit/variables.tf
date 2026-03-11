variable "database" {
  description = "Snowflake database name"
  type        = string
}

variable "schema" {
  description = "Snowflake schema name"
  type        = string
}

variable "stage_name" {
  description = "Name of the stage for Streamlit files"
  type        = string
  default     = "STREAMLIT_STAGE"
}

variable "compute_pool_name" {
  description = "Name of the compute pool for Container Runtime"
  type        = string
  default     = "STREAMLIT_POOL"
}

variable "min_nodes" {
  description = "Minimum number of compute pool nodes"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of compute pool nodes"
  type        = number
  default     = 3
}

variable "auto_suspend_secs" {
  description = "Seconds before auto-suspending the compute pool"
  type        = number
  default     = 3600
}

variable "external_access_integration_name" {
  description = "Name of the external access integration for PyPI"
  type        = string
  default     = "PYPI_ACCESS_INTEGRATION"
}

variable "comment" {
  description = "Comment for resources"
  type        = string
  default     = null
}
