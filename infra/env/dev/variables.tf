variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1"
}

variable "snowflake_private_key_path" {
  description = "Path to the Snowflake private key file"
  type        = string
}

variable "snowflake_database" {
  description = "Snowflake database name"
  type        = string
}

variable "snowflake_warehouse" {
  description = "Snowflake warehouse for Streamlit queries"
  type        = string
}

variable "project_name" {
  description = "Project name used for tagging"
  type        = string
  default     = "streamlit-deploy-poc-multi"
}

variable "owner" {
  description = "Owner identifier used for tagging"
  type        = string
}
