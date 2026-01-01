resource "authentik_user" "service_account" {
  for_each = var.service_accounts
  username = each.key
  name     = try(each.value.name, each.key)
  type     = "service_account"
  path     = try(each.value.path, "service-accounts")
  groups   = try(each.value.groups, [])
}

resource "authentik_token" "service_account" {
  for_each     = var.service_accounts
  identifier   = "${each.key}-token"
  user         = authentik_user.service_account[each.key].id
  description  = try(each.value.token_description, "App password for ${each.key}")
  intent       = "app_password"
  expiring     = try(each.value.token_expiring, false)
  retrieve_key = true
}
