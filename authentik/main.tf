resource "random_string" "client_id" {
  for_each = var.authentik_application
  length   = 40
  special  = false
}

resource "random_password" "client_secret" {
  for_each = var.authentik_application
  length   = 128
  special  = false
}

data "authentik_flow" "default-authorization-flow" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "default-invalidation-flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

data "authentik_certificate_key_pair" "default" {
  name = var.signing_key_name
}

resource "authentik_provider_oauth2" "this" {
  for_each               = var.authentik_application
  name                   = each.key
  client_id              = random_string.client_id[each.key].id
  client_secret          = random_password.client_secret[each.key].result
  authorization_flow     = data.authentik_flow.default-authorization-flow.id
  invalidation_flow      = data.authentik_flow.default-invalidation-flow.id
  refresh_token_validity = var.refresh_token_validity
  allowed_redirect_uris  = each.value.allowed_redirect_uris
  property_mappings      = data.authentik_property_mapping_provider_scope.oauth2.ids
  signing_key            = data.authentik_certificate_key_pair.default.id
  sub_mode               = var.sub_mode
}

resource "authentik_policy_expression" "policy" {
  count      = var.policy_expression != null ? 1 : 0
  name       = var.policy_expression.name
  expression = var.policy_expression.expression
}

resource "authentik_policy_binding" "app-access" {
  for_each = var.policy_expression != null ? var.authentik_application : {}
  target   = authentik_application.this[each.key].uuid
  policy   = authentik_policy_expression.policy[0].id
  order    = 0
}

resource "authentik_application" "this" {
  for_each          = var.authentik_application
  name              = try(each.value.name, each.key)
  slug              = each.key
  meta_icon         = var.app_meta_icon
  protocol_provider = authentik_provider_oauth2.this[each.key].id
}

resource "authentik_group" "this" {
  for_each = var.groups
  name     = each.key
}

resource "authentik_provider_proxy" "this" {
  for_each              = var.proxy_application
  name                  = try(each.value.name, each.key)
  mode                  = each.value.mode
  external_host         = each.value.external_host
  cookie_domain         = each.value.cookie_domain
  skip_path_regex       = each.value.skip_path_regex
  authorization_flow    = data.authentik_flow.default-authorization-flow.id
  invalidation_flow     = data.authentik_flow.default-invalidation-flow.id
  access_token_validity = "hours=24"
}

resource "authentik_application" "proxy" {
  for_each          = var.proxy_application
  name              = try(each.value.name, each.key)
  slug              = each.key
  protocol_provider = authentik_provider_proxy.this[each.key].id
}

resource "authentik_policy_binding" "proxy-access" {
  for_each = var.policy_expression != null ? var.proxy_application : {}
  target   = authentik_application.proxy[each.key].uuid
  policy   = authentik_policy_expression.policy[0].id
  order    = 0
}

resource "authentik_service_connection_docker" "this" {
  count = var.docker_service_connection != null && var.docker_service_connection.name != null ? 1 : 0
  name  = var.docker_service_connection.name
  url   = var.docker_service_connection.url
  local = true
}

locals {
  created_connection_id = one(authentik_service_connection_docker.this[*].id)
  service_connection_id = try(var.docker_service_connection.id, local.created_connection_id)
}

resource "authentik_outpost" "proxy" {
  count              = length(var.proxy_application) > 0 ? 1 : 0
  name               = var.outpost_name
  type               = "proxy"
  service_connection = local.service_connection_id
  protocol_providers = [for k, v in authentik_provider_proxy.this : v.id]
}
