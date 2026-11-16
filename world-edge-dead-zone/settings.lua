data:extend({
  {
    type = "int-setting",
    name = "world-edge-dead-zone-width",
    setting_type = "startup",
    default_value = 32,
    minimum_value = 0,
    maximum_value = 512,
    order = "a"
  },
  {
    type = "string-setting",
    name = "world-edge-dead-zone-tile",
    setting_type = "startup",
    default_value = "grass-1",
    allowed_values = {"grass-1", "dirt-1", "sand-1", "concrete"},
    order = "b"
  },
  {
    type = "bool-setting",
    name = "world-edge-dead-zone-apply-to-width",
    setting_type = "startup",
    default_value = false,
    order = "c"
  },
  {
    type = "bool-setting",
    name = "world-edge-dead-zone-all-surfaces",
    setting_type = "startup",
    default_value = true,
    order = "d"
  }
})
