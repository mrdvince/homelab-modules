output "client_id" {
  value = { for k, v in random_string.client_id : k => v.id }
}

output "client_secret" {
  value     = { for k, v in random_password.client_secret : k => v.result }
  sensitive = true
}

output "proxy_provider_ids" {
  value = { for k, v in authentik_provider_proxy.this : k => v.id }
}

output "outpost_name" {
  value = length(authentik_outpost.proxy) > 0 ? authentik_outpost.proxy[0].name : null
}