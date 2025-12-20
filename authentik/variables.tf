variable "refresh_token_validity" {
  default = "days=1"
}

variable "sub_mode" {
  default = "hashed_user_id"
}

variable "policy_expression" {
  type = map(any)
}

variable "authentik_application" {
  type = map(any)
}

variable "app_meta_icon" {
  default = null
}

variable "groups" {
  type    = map(any)
  default = {}
}

variable "signing_key_name" {
  description = "Name of the certificate key pair for JWT signing"
  default     = "authentik Self-signed Certificate"
}