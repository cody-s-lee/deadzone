-- Mock-engine test of control.lua. Globals expected: CONTROL, H, WD, WS, AX, FILL
math.randomseed(1234)
settings={startup={["world-edge-dead-zone-width"]={value=WS},["world-edge-dead-zone-tile"]={value=FILL},
  ["world-edge-dead-zone-apply-to-width"]={value=AX},["world-edge-dead-zone-all-surfaces"]={value=true}}}
local handlers={}
script={on_init=function(f) handlers.init=f end,on_configuration_changed=function(f) handlers.cfg=f end,
        on_event=function(id,f) handlers[id]=f end}
defines={events={on_player_joined_game="pj",on_chunk_generated="cg",on_surface_created="sc",on_biter_base_built="bb"}}
storage={}; log=function() end; serpent={line=tostring}
local printed={}
local S={name="nauvis",map_gen_settings={height=H,width=WD},tiles={},ents={},decos={},chunks={}}
local function in_map(x,y)
  if H>0 and (y< -H/2 or y>=H/2) then return false end
  if WD>0 and (x< -WD/2 or x>=WD/2) then return false end
  return true end
function S.get_tile(x,y) return {name=S.tiles[x..","..y] or "void"} end
function S.set_tiles(list,correct)
  assert(correct==false)
  for _,t in ipairs(list) do
    assert(in_map(t.position[1],t.position[2]),"touched void tile")
    S.tiles[t.position[1]..","..t.position[2]]=t.name end end
local function inarea(x,y,a) return x>=a[1][1] and x<a[2][1] and y>=a[1][2] and y<a[2][2] end
function S.find_entities_filtered(f)
  local set={}; for _,t in ipairs(f.type) do set[t]=true end
  local out={}
  for _,e in ipairs(S.ents) do
    if e.valid and set[e.type] and inarea(e.x,e.y,f.area) and (not f.force or e.force==f.force) then out[#out+1]=e end end
  return out end
function S.destroy_decoratives(f) for _,d in ipairs(S.decos) do if d.valid and inarea(d.x,d.y,f.area) then d.valid=false end end end
function S.get_chunks() local i=0; return function() i=i+1; return S.chunks[i] end end
function S.is_chunk_generated() return true end
game={surfaces={nauvis=S},print=function(m) printed[#printed+1]=m[1] end}
local function ent(t,x,y,force) local e={type=t,x=x,y=y,force=force,valid=true}; function e.destroy() e.valid=false end; S.ents[#S.ents+1]=e end
local function gen(cx,cy)
  for y=cy*32,cy*32+31 do for x=cx*32,cx*32+31 do
    if in_map(x,y) then S.tiles[x..","..y]=(math.random()<0.5) and "deepwater" or "lava" end end end
  local types={"resource","cliff","tree","plant","simple-entity","fish"}
  for i=1,400 do local x,y=cx*32+math.random()*32,cy*32+math.random()*32
    if in_map(math.floor(x),math.floor(y)) then ent(types[math.random(#types)],x,y,"neutral") end end
  for i=1,40 do local x,y=cx*32+math.random()*32,cy*32+math.random()*32
    if in_map(math.floor(x),math.floor(y)) then
      ent(i%2==0 and "unit-spawner" or "turret",x,y,"enemy")
      ent("turret",x,y,"player")      -- player gun turret must survive
      ent("assembling-machine",x,y,"player")
      S.decos[#S.decos+1]={x=x,y=y,valid=true} end end
  S.chunks[#S.chunks+1]={x=cx,y=cy}
end
dofile(CONTROL)
handlers.init()
local R=function(extent) return extent>0 and (extent//64+3) or 6 end
for cy=-R(H),R(H)-1 do for cx=-R(WD),R(WD)-1 do
  gen(cx,cy); handlers.cg({surface=S,position={x=cx,y=cy}}) end end

-- expected effective widths
local function eff(ext) if ext<=0 or WS<=0 then return 0 end local m=(ext-32)//2; if WS>m then return math.max(m,0) end return WS end
local ey=eff(H); local ex=AX and eff(WD) or 0
local function zone(x,y)
  if H>0 and ey>0 and (y<math.ceil(-H/2)+ey or y>math.ceil(H/2)-1-ey) then return true end
  if AX and WD>0 and ex>0 and (x<math.ceil(-WD/2)+ex or x>math.ceil(WD/2)-1-ex) then return true end
  return false end
local zt,bad_t,keep_t,bad_keep=0,0,0,0
for k,name in pairs(S.tiles) do
  local x,y=k:match("(-?%d+),(-?%d+)"); x,y=tonumber(x),tonumber(y)
  if zone(x,y) then zt=zt+1; if name~=FILL then bad_t=bad_t+1 end
  else keep_t=keep_t+1; if name~="deepwater" and name~="lava" then bad_keep=bad_keep+1 end end
end
local ze,bad_e,kept_player,lost_player,kept_nat,lost_nat,zd,bad_d=0,0,0,0,0,0,0,0
for _,e in ipairs(S.ents) do
  local z=zone(math.floor(e.x),math.floor(e.y))
  if e.force=="player" then if e.valid then kept_player=kept_player+1 else lost_player=lost_player+1 end
  elseif z then ze=ze+1; if e.valid then bad_e=bad_e+1 end
  else if e.valid then kept_nat=kept_nat+1 else lost_nat=lost_nat+1 end end
end
for _,d in ipairs(S.decos) do if zone(math.floor(d.x),math.floor(d.y)) then zd=zd+1; if d.valid then bad_d=bad_d+1 end end end
print(string.format("H=%d W=%d width_setting=%d apply_x=%s fill=%s -> effective y-width=%d x-width=%d",H,WD,WS,tostring(AX),FILL,ey,ex))
print(string.format("  zone tiles: %d, not fill: %d | outside-zone tiles: %d, wrongly altered: %d",zt,bad_t,keep_t,bad_keep))
print(string.format("  zone neutral/enemy entities: %d, survivors: %d | outside destroyed wrongly: %d | player entities lost: %d",ze,bad_e,lost_nat,lost_player))
print(string.format("  zone decoratives: %d, survivors: %d | warnings: %d",zd,bad_d,#printed))
for _,w in ipairs(printed) do print("   warn:",w) end
-- biter expansion inside zone
local tgt=ey>0 and {type="unit-spawner",x=0.5,y=-H//2+1.5,force="enemy"} or nil
if tgt then local d=false; tgt.valid=true; tgt.surface=S; tgt.position={x=tgt.x,y=tgt.y}; function tgt.destroy() tgt.valid=false end
  handlers.bb({entity=tgt}); print("  expansion base in zone destroyed:",not tgt.valid) end
assert(bad_t==0 and bad_e==0 and bad_d==0 and bad_keep==0 and lost_nat==0 and lost_player==0,"FAILED")
print("  PASS")
