-- World Edge Dead Zone: keeps a band along finite map edges free of everything but a fill tile.
-- Runtime-only on purpose: map width/height are not visible to data-stage noise expressions,
-- so the edge position cannot be baked into autoplace expressions. See README.

local MIN_PLAYABLE = 32
local CHUNK = 32

-- Entity types removed inside the zone. Neutral-force content:
local NEUTRAL_TYPES = {"resource", "cliff", "tree", "plant", "simple-entity", "fish"}
-- Enemy content (filtered to the enemy force so player turrets are never touched):
local ENEMY_TYPES = {"unit-spawner", "turret"}

local function setting(name) return settings.startup["world-edge-dead-zone-" .. name].value end

local function is_platform(surface)
  local ok, platform = pcall(function() return surface.platform end)
  return ok and platform ~= nil
end

local function surface_enabled(surface)
  if is_platform(surface) then return false end
  if not setting("all-surfaces") and surface.name ~= "nauvis" then return false end
  return true
end

-- Computes the zone for a surface. Returns (zone|nil, warnings). zone = {x = axis?, y = axis?, bx, by}
-- where an axis is {lo, hi, w}: tile indices [lo, hi] are inside the map and the zone is
-- [lo, lo+w-1] and [hi-w+1, hi]; bx/by are the raw map bounds ({lo, hi}) of each finite axis.
local function compute_zone(surface)
  local width = setting("width")
  if width <= 0 or not surface_enabled(surface) then return nil, {} end
  local mgs = surface.map_gen_settings
  local zone, warnings = {}, {}
  -- Real map bounds (tile indices, inclusive) on each finite axis, used to never touch void tiles.
  if mgs.width and mgs.width > 0 then
    zone.bx = {lo = math.ceil(-mgs.width / 2), hi = math.ceil(mgs.width / 2) - 1}
  end
  if mgs.height and mgs.height > 0 then
    zone.by = {lo = math.ceil(-mgs.height / 2), hi = math.ceil(mgs.height / 2) - 1}
  end
  local function axis(key, label, extent)
    if not extent or extent <= 0 then return end
    local w = width
    local max_w = math.floor((extent - MIN_PLAYABLE) / 2)
    if w > max_w then
      if max_w <= 0 then
        warnings[#warnings + 1] = {"world-edge-dead-zone.disabled-axis", surface.name, label, extent, MIN_PLAYABLE}
        return
      end
      warnings[#warnings + 1] = {"world-edge-dead-zone.clamped", surface.name, label, extent, w, max_w, MIN_PLAYABLE}
      w = max_w
    end
    -- Edges are at +-extent/2. ceil/floor keep us strictly inside the map for odd sizes.
    local lo = math.ceil(-extent / 2)
    local hi = math.ceil(extent / 2) - 1
    zone[key] = {lo = lo, hi = hi, w = w}
  end
  axis("y", "height", mgs.height)
  if setting("apply-to-width") then axis("x", "width", mgs.width) end
  if not zone.x and not zone.y then return nil, warnings end
  return zone, warnings
end

-- Is tile (x,y) (integer tile indices) inside the zone?
local function in_zone(zone, x, y)
  local a = zone.y
  if a and (y < a.lo + a.w or y > a.hi - a.w) and y >= a.lo and y <= a.hi then return true end
  a = zone.x
  if a and (x < a.lo + a.w or x > a.hi - a.w) and x >= a.lo and x <= a.hi then return true end
  return false
end

-- Rectangles (left,top,right,bottom; right/bottom exclusive, in tiles) of the zone clipped to `area`.
local function zone_rects(zone, l, t, r, b)
  local rects = {}
  local function add(x1, y1, x2, y2)
    x1, y1, x2, y2 = math.max(x1, l), math.max(y1, t), math.min(x2, r), math.min(y2, b)
    if zone.bx then x1, x2 = math.max(x1, zone.bx.lo), math.min(x2, zone.bx.hi + 1) end
    if zone.by then y1, y2 = math.max(y1, zone.by.lo), math.min(y2, zone.by.hi + 1) end
    if x1 < x2 and y1 < y2 then rects[#rects + 1] = {x1, y1, x2, y2} end
  end
  local ya, xa = zone.y, zone.x
  local INF = 1e9
  if ya then
    add(-INF, ya.lo, INF, ya.lo + ya.w)
    add(-INF, ya.hi - ya.w + 1, INF, ya.hi + 1)
  end
  if xa then
    -- avoid double-covering corners already added by the y rects
    local y1, y2 = -INF, INF
    if ya then y1, y2 = ya.lo + ya.w, ya.hi - ya.w + 1 end
    add(xa.lo, y1, xa.lo + xa.w, y2)
    add(xa.hi - xa.w + 1, y1, xa.hi + 1, y2)
  end
  return rects
end

local function clean_entities(surface, rect)
  local area = {{rect[1], rect[2]}, {rect[3], rect[4]}}
  for _, e in pairs(surface.find_entities_filtered{area = area, type = NEUTRAL_TYPES}) do
    if e.valid then e.destroy() end
  end
  for _, e in pairs(surface.find_entities_filtered{area = area, type = ENEMY_TYPES, force = "enemy"}) do
    if e.valid then e.destroy() end
  end
  surface.destroy_decoratives{area = area}
end

-- retroactive = true: preserve player-placed tiles (they have a hidden tile underneath)
local function process_area(surface, zone, l, t, r, b, retroactive)
  local fill = setting("tile")
  for _, rect in pairs(zone_rects(zone, l, t, r, b)) do
    local tiles, n = {}, 0
    for y = rect[2], rect[4] - 1 do
      for x = rect[1], rect[3] - 1 do
        local set = true
        if retroactive then
          local tile = surface.get_tile(x, y)
          set = tile.name ~= fill and tile.hidden_tile == nil
        end
        if set then
          n = n + 1
          tiles[n] = {name = fill, position = {x, y}}
        end
      end
    end
    if n > 0 then surface.set_tiles(tiles, false, false, false) end
    clean_entities(surface, rect)
  end
end

local function process_chunk(surface, chunk_x, chunk_y, retroactive)
  local zone = compute_zone(surface)
  if not zone then return end
  local l, t = chunk_x * CHUNK, chunk_y * CHUNK
  process_area(surface, zone, l, t, l + CHUNK, t + CHUNK, retroactive)
end

local function process_existing(surface)
  local zone = compute_zone(surface)
  if not zone then return end
  for chunk in surface.get_chunks() do
    local l, t = chunk.x * CHUNK, chunk.y * CHUNK
    if #zone_rects(zone, l, t, l + CHUNK, t + CHUNK) > 0 and surface.is_chunk_generated(chunk) then
      process_area(surface, zone, l, t, l + CHUNK, t + CHUNK, true)
    end
  end
end

local function collect_warnings()
  storage.warnings = {}
  for _, surface in pairs(game.surfaces) do
    local _, warnings = compute_zone(surface)
    for _, w in pairs(warnings) do storage.warnings[#storage.warnings + 1] = w end
  end
end

local function signature()
  return table.concat({setting("width"), setting("tile"), tostring(setting("apply-to-width")), tostring(setting("all-surfaces"))}, "|")
end

local function process_all_existing()
  for _, surface in pairs(game.surfaces) do process_existing(surface) end
  storage.signature = signature()
  collect_warnings()
  for _, w in pairs(storage.warnings) do
    game.print(w)
    log(serpent.line(w))
  end
end

script.on_init(function()
  storage.warned_players = {}
  process_all_existing()
end)

script.on_configuration_changed(function()
  storage.warned_players = storage.warned_players or {}
  -- Runs once per version/settings change; also covers the mod being added to a save.
  if storage.signature ~= signature() then process_all_existing() end
end)

-- Chat is usually empty during on_init, so repeat any warnings once per player on first join.
script.on_event(defines.events.on_player_joined_game, function(e)
  storage.warned_players = storage.warned_players or {}
  if storage.warned_players[e.player_index] then return end
  storage.warned_players[e.player_index] = true
  local player = game.get_player(e.player_index)
  for _, w in pairs(storage.warnings or {}) do player.print(w) end
end)

script.on_event(defines.events.on_chunk_generated, function(e)
  process_chunk(e.surface, e.position.x, e.position.y, false)
end)

script.on_event(defines.events.on_surface_created, function(e)
  -- Chunks of the new surface arrive through on_chunk_generated; just record clamp warnings.
  local surface = game.get_surface(e.surface_index)
  if not surface then return end
  local _, warnings = compute_zone(surface)
  storage.warnings = storage.warnings or {}
  for _, w in pairs(warnings) do
    storage.warnings[#storage.warnings + 1] = w
    game.print(w)
  end
  process_existing(surface)
end)

-- Enemy expansion can found bases in already-generated chunks; remove any inside a zone.
script.on_event(defines.events.on_biter_base_built, function(e)
  local entity = e.entity
  if not (entity and entity.valid) then return end
  local zone = compute_zone(entity.surface)
  if not zone then return end
  local p = entity.position
  if in_zone(zone, math.floor(p.x), math.floor(p.y)) then entity.destroy() end
end)
