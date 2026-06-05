variable "project_name" {
  description = "Base name used as prefix for network resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability Zones to spread subnets across."
  type        = list(string)
}
