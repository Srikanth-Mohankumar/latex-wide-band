-- wideband.lua -- proof of concept, LuaLaTeX only
--
-- Node-level support for the wideband LaTeX package:
--   * mark(reserve)          insert marker whatsit + reservation kern + penalty
--                            into the current (vertical) list
--   * find(boxnum)           scan top level of a column box for the marker;
--                            report position (glue-set-aware) back to TeX
--   * split(src,top,bot,h,botgoal)
--                            cut the stored left column at the marker,
--                            drop marker/kern/penalty/leading glue, and
--                            repack into two box registers
--   * strip(boxnum)          remove marker material in place (fallback path)
--
-- Communication back to TeX goes through two registers whose numbers are
-- handed over once via setup{}.

local wideband = {}

local WHATSIT = node.id("whatsit")
local KERN    = node.id("kern")
local GLUE    = node.id("glue")
local PENALTY = node.id("penalty")
local UD      = node.subtype and node.subtype("user_defined") or 8

-- unique tag for our marker whatsit
local USER_ID = 0x57424e44 -- "WBND"

local reg = { found = nil, h = nil }

function wideband.setup(t)
  reg.found = assert(tonumber(t.found), "wideband: bad count register")
  reg.h     = assert(tonumber(t.h),     "wideband: bad dimen register")
end

local function info(msg)
  texio.write_nl("log", "Package wideband info: " .. msg)
end

----------------------------------------------------------------------
-- marker insertion (called in vertical mode, main galley)
----------------------------------------------------------------------
function wideband.mark(reserve)
  reserve = tonumber(reserve) or 0
  local w = node.new(WHATSIT, UD)
  w.user_id = USER_ID
  w.type    = 100          -- value is a number
  w.value   = reserve
  local k = node.new(KERN, 1)   -- explicit kern
  k.kern = reserve
  local p = node.new(PENALTY)
  p.penalty = 10000             -- forbid a break right after the reservation
  node.write(w)
  node.write(k)
  node.write(p)
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function find_marker(head)
  local first, count = nil, 0
  for n in node.traverse_id(WHATSIT, head) do
    if n.subtype == UD and n.user_id == USER_ID then
      count = count + 1
      if not first then first = n end
    end
  end
  return first, count
end

local HLIST, VLIST, RULE = node.id("hlist"), node.id("vlist"), node.id("rule")

-- vertical distance from the top of a packaged vbox to node `stop`,
-- honouring the box's glue setting (this is what \vpack did)
local function vpos(box, stop)
  local d, gs, sign, order = 0, box.glue_set, box.glue_sign, box.glue_order
  for n in node.traverse(box.list) do
    if n == stop then return d end
    local id = n.id
    if id == HLIST or id == VLIST or id == RULE then
      d = d + (n.height or 0) + (n.depth or 0)
    elseif id == KERN then
      d = d + n.kern
    elseif id == GLUE then
      local g = n.width
      if sign == 1 and n.stretch_order == order then
        g = g + gs * n.stretch
      elseif sign == 2 and n.shrink_order == order then
        g = g - gs * n.shrink
      end
      d = d + g
    end
  end
  return d
end

----------------------------------------------------------------------
-- find: scan a packaged column box (top level only)
-- sets \wb@found (0/1) and \wb@h (distance from top of box to marker,
-- honouring the box's glue setting)
----------------------------------------------------------------------
function wideband.find(boxnum)
  local b = tex.box[boxnum]
  local found, h = 0, 0
  if b and b.list then
    local m, count = find_marker(b.list)
    if m then
      found = count           -- >1 signals "multiple bands on one page"
      h = vpos(b, m)
      info("marker found at " .. (h / 65536) .. "pt from column top")
    end
  end
  tex.setcount("global", reg.found, found)
  tex.setdimen("global", reg.h, h)
end

----------------------------------------------------------------------
-- split: cut the stored left column at the marker
--   src      box register holding the left column (consumed)
--   topreg   receives everything above the marker, packed to h exactly
--   botreg   receives everything below, packed to botgoal exactly
----------------------------------------------------------------------
function wideband.split(src, topreg, botreg, h, botgoal)
  h, botgoal = tonumber(h) or 0, tonumber(botgoal) or 0
  local b = tex.box[src]
  if not (b and b.list) then
    info("split: source box empty")
    return
  end
  local head = b.list
  b.list = nil            -- detach before the register is freed
  tex.box[src] = nil

  local m = find_marker(head)
  if not m then           -- should not happen; put things back
    tex.box[src] = node.vpack(head)
    return
  end

  -- cut the list just before the marker
  local top_head = head
  if m == head then top_head = nil end
  if m.prev then m.prev.next = nil end

  -- walk past marker, reservation kern, guard penalties and the now
  -- stale interline/parskip glue
  local rest = m.next
  m.prev, m.next = nil, nil
  node.free(m)
  if rest and rest.id == KERN then
    local t = rest; rest = rest.next
    t.prev, t.next = nil, nil; node.free(t)
  end
  while rest and (rest.id == PENALTY or rest.id == GLUE) do
    local t = rest; rest = rest.next
    t.prev, t.next = nil, nil; node.free(t)
  end
  if rest then rest.prev = nil end

  local function empty() local k = node.new(KERN, 1); k.kern = 0; return k end
  local topbox = node.vpack(top_head or empty(), h, "exactly")
  local botbox = node.vpack(rest or empty(), botgoal, "exactly")
  tex.setbox("global", topreg, topbox)
  tex.setbox("global", botreg, botbox)
end

----------------------------------------------------------------------
-- strip: remove marker material from a box in place (fallback when the
-- band ended up in the second column)
----------------------------------------------------------------------
function wideband.strip(boxnum)
  local b = tex.box[boxnum]
  if not (b and b.list) then return end
  local m = find_marker(b.list)
  if not m then return end
  local head = b.list
  local function drop(n)
    local nxt = n.next
    head = node.remove(head, n)
    node.free(n)
    return nxt
  end
  local n = m.next
  drop(m)
  if n and n.id == KERN then n = drop(n) end
  if n and n.id == PENALTY then drop(n) end
  b.list = head
end

return wideband
