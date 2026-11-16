-- Paste into the console as: /c <contents>  (or run via --run-script after exploring).
-- Force-generates the whole map, then counts anything forbidden inside the zone.
local s = game.surfaces.nauvis
local H = s.map_gen_settings.height
local w = settings.startup["world-edge-dead-zone-width"].value
w = math.min(w, math.floor((H - 32) / 2))
s.request_to_generate_chunks({0, 0}, math.ceil(H / 64) + 4)
s.force_generate_chunk_requests()
local bad = {}
local function count(label, n) bad[label] = (bad[label] or 0) + n end
for _, band in pairs{{{-4096, -H / 2}, {4096, -H / 2 + w}}, {{-4096, H / 2 - w}, {4096, H / 2}}} do
  count("resource", s.count_entities_filtered{area = band, type = "resource"})
  count("cliff", s.count_entities_filtered{area = band, type = "cliff"})
  count("tree", s.count_entities_filtered{area = band, type = {"tree", "plant"}})
  count("rock", s.count_entities_filtered{area = band, type = "simple-entity"})
  count("enemy", s.count_entities_filtered{area = band, type = {"unit-spawner", "turret"}, force = "enemy"})
  count("non-fill tiles", s.count_tiles_filtered{area = band, name = settings.startup["world-edge-dead-zone-tile"].value, invert = true})
  count("water tiles", s.count_tiles_filtered{area = band, collision_mask = "water_tile"})
  count("decoratives", #s.find_decoratives_filtered{area = band})
end
game.print(serpent.line(bad))
