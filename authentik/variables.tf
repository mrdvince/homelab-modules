variable "refresh_token_validity" {
  default = "days=1"
}

variable "sub_mode" {
  default = "hashed_user_id"
}

variable "policy_expression" {
  type    = map(any)
  default = null
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

variable "proxy_application" {
  description = "Map of proxy applications for forward auth"
  type = map(object({
    name            = optional(string)
    external_host   = string
    mode            = optional(string, "forward_single")
    cookie_domain   = optional(string)
    skip_path_regex = optional(string)
  }))
  default = {}
}

variable "outpost_name" {
  description = "Name of the outpost for proxy providers"
  default     = "forward-auth-outpost"
}

variable "docker_service_connection" {
  description = "Docker service connection config. Use 'id' to reference existing, or 'name' to create new."
  type = object({
    id   = optional(string)
    name = optional(string)
    url  = optional(string, "unix:///var/run/docker.sock")
  })
  default = null
}

variable "service_accounts" {
  description = "Map of service accounts for machine-to-machine authentication"
  type = map(object({
    name              = optional(string)
    path              = optional(string, "service-accounts")
    groups            = optional(list(string), [])
    token_description = optional(string)
    token_expiring    = optional(bool, false)
  }))
  default = {}
}