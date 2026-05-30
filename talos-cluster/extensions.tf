data "talos_image_factory_extensions_versions" "this" {
  count         = length(var.extensions) > 0 ? 1 : 0
  talos_version = var.talos_version
  filters = {
    names = var.extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    length(var.extensions) > 0 ? {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this[0].extensions_info[*].name
        }
      }
    } : {}
  )
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}
