-- wideband.lua -- node-level support for wideband.sty (stratum model, v0.5)
--
-- LuaLaTeX only.  Everything here is measurement, exact cutting and
-- bookkeeping; the page logic itself lives in wideband.sty.
--
-- Vertical position accounting follows TeX's page builder exactly:
--     box/rule : total += depth + height ; depth = node.depth   (clipped to \maxdepth)
--     kern/glue: total += depth + amount ; depth = 0
--     others   : no contribution
-- so `total` at a node equals TeX's \pagetotal there, i.e. the set height a
-- \vbox holding everything above that node would need.  (node.dimensions
-- measures HORIZONTALLY and must never be used for this.)
--
-- Legal vertical breakpoints, again as in TeX:
--     glue    : legal iff the preceding node is not discardable
--     kern    : legal iff followed by glue
--     penalty : legal iff penalty < 10000
--
-- Communication with TeX goes through registers whose numbers are handed
-- over once by wideband.setup{}.

local wideband = {}

local N       = node
local WHATSIT = N.id("whatsit")
local KERN    = N.id("kern")
local GLUE    = N.id("glue")
local PENALTY = N.id("penalty")
local HLIST   = N.id("hlist")
local VLIST   = N.id("vlist")
local RULE    = N.id("rule")
local MATHN   = N.id("math")
local UD      = (N.subtype and N.subtype("user_defined")) or 8

-- "WBND": the band request marker
local USER_ID = 0x57424E44

local INF_PENALTY = 10000
local NA          = -2147483647   -- "not applicable" sentinel for log fields

local reg = {}

function wideband.setup(t)
  for k, v in pairs(t) do reg[k] = tonumber(v) end
end

local function setcount(name, v) tex.setcount("global", reg[name], v) end
local function setdimen(name, v) tex.setdimen("global", reg[name], v) end

----------------------------------------------------------------------
-- generic vertical walk
----------------------------------------------------------------------

local function discardable(id)
  return id == GLUE or id == KERN or id == PENALTY or id == MATHN
end

-- visit(n, total, prev) for every node; returns natural height and depth
local function vscan(head, maxdepth, visit)
  local total, depth = 0, 0
  local prev = nil
  local n = head
  while n do
    if visit then visit(n, total, prev) end
    local id = n.id
    if id == HLIST or id == VLIST or id == RULE then
      total = total + depth + (n.height or 0)
      depth = n.depth or 0
      if depth > maxdepth then
        total = total + depth - maxdepth
        depth = maxdepth
      end
    elseif id == GLUE then
      total = total + depth + (n.width or 0)
      depth = 0
    elseif id == KERN then
      total = total + depth + (n.kern or 0)
      depth = 0
    end
    prev = n
    n = n.next
  end
  return total, depth
end

local function legal(n, prev)
  local id = n.id
  if id == GLUE then
    return prev ~= nil and not discardable(prev.id)
  elseif id == KERN then
    return n.next ~= nil and n.next.id == GLUE
  elseif id == PENALTY then
    return (n.penalty or 0) < INF_PENALTY
  end
  return false
end

local function maxdepth()
  local m = tex.maxdepth
  if m == nil or m <= 0 then m = 4 * 65536 end
  return m
end

local function zerokern()
  local k = N.new(KERN, 1)
  k.kern = 0
  return k
end

local function is_marker(n)
  return n.id == WHATSIT and n.subtype == UD and n.user_id == USER_ID
end

----------------------------------------------------------------------
-- the request marker
----------------------------------------------------------------------

-- called in vertical mode on the main vertical list, from \directlua
function wideband.mark(id)
  local w = N.new(WHATSIT, UD)
  w.user_id = USER_ID
  w.type    = 100                -- value is a number
  w.value   = tonumber(id) or 0
  N.write(w)
end

-- report the first marker of a box: \wb@found = number of markers,
-- \wb@bid = its band id, \wb@h = its vertical position
function wideband.markinfo(boxnum)
  local b = tex.box[boxnum]
  local cnt, pos, bid = 0, 0, 0
  if b and b.list then
    vscan(b.list, maxdepth(), function(n, total)
      if is_marker(n) then
        cnt = cnt + 1
        if cnt == 1 then pos = total; bid = n.value or 0 end
      end
    end)
  end
  setcount("found", cnt)
  setcount("bid", bid)
  setdimen("h", pos)
end

-- remove every marker from the top level of a box
function wideband.strip(boxnum)
  local b = tex.box[boxnum]
  if not (b and b.list) then return end
  local head = b.list
  local n = head
  while n do
    local nxt = n.next
    if is_marker(n) then
      head = N.remove(head, n)
      n.next, n.prev = nil, nil
      N.free(n)
    end
    n = nxt
  end
  b.list = head
end

-- drop discardables from the head of a box's list (the \topskip glue and
-- friends that the page builder put at the top of a column)
function wideband.striptop(boxnum)
  local b = tex.box[boxnum]
  if not (b and b.list) then return end
  local head = b.list
  while head and discardable(head.id) do
    local nxt = head.next
    head.next, head.prev = nil, nil
    N.free(head)
    head = nxt
  end
  if head then head.prev = nil end
  b.list = head
end

----------------------------------------------------------------------
-- measurement
----------------------------------------------------------------------

function wideband.natheight(boxnum)
  local b = tex.box[boxnum]
  local t, d = 0, 0
  if b and b.list then t, d = vscan(b.list, maxdepth(), nil) end
  setdimen("nat", t)
  setdimen("natdp", d)
end

----------------------------------------------------------------------
-- legal-cut search and exact cut
----------------------------------------------------------------------

local function subtree_has_attr(n, a)
  while n do
    if N.has_attribute(n, a) then return true end
    local id = n.id
    if id == HLIST or id == VLIST then
      if n.list and subtree_has_attr(n.list, a) then return true end
    end
    n = n.next
  end
  return false
end

local function find_break(head, ymin, ymax)
  local best, bestpos = nil, 0
  vscan(head, maxdepth(), function(n, total, prev)
    if best == nil and total >= ymin and (ymax == nil or total <= ymax)
       and legal(n, prev) then
      best, bestpos = n, total
    end
  end)
  return best, bestpos
end

-- Search only.  Sets \wb@found (0/1), \wb@cuty and \wb@flags:
--   0  no footnote callout anywhere in the list (cannot prove safety)
--   1  callouts exist and all of them are above the cut
--   2  a callout sits below the cut, so it would change column
function wideband.probe(src, ymin, ymax)
  ymin, ymax = tonumber(ymin), tonumber(ymax)
  local b = tex.box[src]
  local best, pos = nil, 0
  if b and b.list then best, pos = find_break(b.list, ymin, ymax) end
  local flags = 0
  if best and reg.fnattr then
    if subtree_has_attr(best, reg.fnattr) then
      flags = 2
    elseif subtree_has_attr(b.list, reg.fnattr) then
      flags = 1
    end
  end
  setcount("found", best and 1 or 0)
  setcount("flags", flags)
  setdimen("cuty", pos)
end

-- Exact cut of box `src` at the first legal breakpoint at or after y.
-- topreg receives everything above, botreg the tail; the discardables at the
-- break are pruned as a page break would prune them.
function wideband.docut(src, y, topreg, botreg)
  y = tonumber(y)
  local b = tex.box[src]
  if not (b and b.list) then
    setcount("found", 0)
    return
  end
  local head = b.list
  b.list = nil
  tex.box[src] = nil

  local best = find_break(head, y, nil)
  if not best then
    tex.setbox("global", topreg, N.vpack(head))
    tex.setbox("global", botreg, N.vpack(zerokern()))
    setcount("found", 0)
    return
  end

  local tophead = head
  local p = best.prev
  if p then
    p.next = nil
    best.prev = nil
  else
    tophead = nil
  end

  local rest = best
  while rest and discardable(rest.id) do
    local nxt = rest.next
    rest.next, rest.prev = nil, nil
    N.free(rest)
    rest = nxt
  end
  if rest then rest.prev = nil end

  local topbox = N.vpack(tophead or zerokern())
  local botbox = N.vpack(rest or zerokern())
  tex.setbox("global", topreg, topbox)
  tex.setbox("global", botreg, botbox)
  setdimen("topnat", topbox.height)
  setdimen("topdp", topbox.depth)
  setdimen("botnat", botbox.height)
  setdimen("botdp", botbox.depth)
  setcount("found", 1)
end

----------------------------------------------------------------------
-- decision record and sidecar
----------------------------------------------------------------------

local records = {
  version   = 1,
  gate      = { status = "unknown", reason = "not-checked" },
  decisions = {},
  pages     = {},
}

local function pt(v)
  v = tonumber(v)
  if v == nil or v == NA then return nil end
  return v / 65536
end

-- TeX's print_scaled, so that log fields are byte-identical to \the<dimen>
local function print_scaled(s)
  local sign = ""
  if s < 0 then sign = "-"; s = -s end
  local out = { tostring(s // 65536), "." }
  s = 10 * (s % 65536) + 5
  local delta = 10
  repeat
    if delta > 65536 then s = s + 32768 - 50000 end
    out[#out + 1] = tostring(s // 65536)
    s = 10 * (s % 65536)
    delta = delta * 10
  until s <= delta
  return sign .. table.concat(out)
end

local function dim(v)
  v = tonumber(v)
  if v == nil or v == NA then return "-" end
  return print_scaled(v) .. "pt"
end

function wideband.gate(status, reason)
  records.gate = { status = tostring(status), reason = tostring(reason) }
end

function wideband.decision(id, page, col, stratum,
                           h, S, R, B, P, ymin, ymax, y,
                           result, code, note)
  records.decisions[#records.decisions + 1] = {
    id = tonumber(id), page = tonumber(page),
    col = tonumber(col), stratum = tonumber(stratum),
    h = pt(h), S = pt(S), R = pt(R), B = pt(B), P = pt(P),
    ymin = pt(ymin), ymax = pt(ymax), y = pt(y),
    result = tostring(result), code = tostring(code), note = tostring(note),
  }
  texio.write_nl("log", table.concat({
    "WIDEBAND DECISION:",
    "id=" .. tostring(id),
    "page=" .. tostring(page),
    "col=" .. tostring(col),
    "stratum=" .. tostring(stratum),
    "h=" .. dim(h),
    "S=" .. dim(S),
    "R=" .. dim(R),
    "B=" .. dim(B),
    "P=" .. dim(P),
    "ymin=" .. dim(ymin),
    "ymax=" .. dim(ymax),
    "y=" .. dim(y),
    "result=" .. tostring(result),
    "code=" .. tostring(code),
    "note=" .. tostring(note),
  }, " "))
end

local currows = nil

function wideband.pagerow(kind, height, bid, y)
  currows = currows or {}
  currows[#currows + 1] = {
    kind = kind, h = tonumber(height) or 0,
    id = tonumber(bid), y = tonumber(y),
  }
end

function wideband.pageend(page)
  if not currows then return end
  local rows = currows
  currows = nil
  -- normalise so that the row sequence alternates stratum, band, stratum, ...
  if rows[1] and rows[1].kind == "band" then
    table.insert(rows, 1, { kind = "stratum", h = 0 })
  end
  if rows[#rows] and rows[#rows].kind == "band" then
    rows[#rows + 1] = { kind = "stratum", h = 0 }
  end
  local rec = { page = tonumber(page), strata = {}, bands = {} }
  local heights, ids = {}, {}
  for _, r in ipairs(rows) do
    heights[#heights + 1] = dim(r.h)
    if r.kind == "band" then
      rec.bands[#rec.bands + 1] = { id = r.id, y = pt(r.y), B = pt(r.h) }
      ids[#ids + 1] = tostring(r.id)
    else
      rec.strata[#rec.strata + 1] = { height = pt(r.h) }
    end
  end
  records.pages[#records.pages + 1] = rec
  if #rec.bands > 0 then
    texio.write_nl("log", string.format(
      "WIDEBAND PAGE: page=%s strata=%d bands=%s heights=%s",
      tostring(page), #rec.strata,
      table.concat(ids, ","), table.concat(heights, ",")))
  end
end

local function jstr(s)
  return '"' .. (tostring(s):gsub('[\\"]', '\\%0')) .. '"'
end

local function jnum(v)
  if v == nil then return "null" end
  return string.format("%.4f", v)
end

local function write_sidecar()
  local name = tex.jobname .. ".wideband.json"
  local f = io.open(name, "w")
  if not f then return end
  f:write('{"version": ', tostring(records.version), ',\n')
  f:write(' "gate": {"status": ', jstr(records.gate.status),
          ', "reason": ', jstr(records.gate.reason), '},\n')
  f:write(' "decisions": [')
  for i, d in ipairs(records.decisions) do
    if i > 1 then f:write(',\n               ') end
    f:write('{"id": ', tostring(d.id),
            ', "page": ', tostring(d.page),
            ', "col": ', tostring(d.col),
            ', "stratum": ', tostring(d.stratum),
            ', "h": ', jnum(d.h),
            ', "S": ', jnum(d.S),
            ', "R": ', jnum(d.R),
            ', "B": ', jnum(d.B),
            ', "P": ', jnum(d.P),
            ', "ymin": ', jnum(d.ymin),
            ', "ymax": ', jnum(d.ymax),
            ', "y": ', jnum(d.y),
            ', "result": ', jstr(d.result),
            ', "code": ', jstr(d.code),
            ', "note": ', jstr(d.note), '}')
  end
  f:write('],\n')
  f:write(' "pages": [')
  for i, p in ipairs(records.pages) do
    if i > 1 then f:write(',\n           ') end
    f:write('{"page": ', tostring(p.page), ', "strata": [')
    for j, s in ipairs(p.strata) do
      if j > 1 then f:write(', ') end
      f:write('{"height": ', jnum(s.height), '}')
    end
    f:write('], "bands": [')
    for j, bb in ipairs(p.bands) do
      if j > 1 then f:write(', ') end
      f:write('{"id": ', tostring(bb.id),
              ', "y": ', jnum(bb.y),
              ', "B": ', jnum(bb.B), '}')
    end
    f:write(']}')
  end
  f:write(']}\n')
  f:close()
end

if luatexbase and luatexbase.add_to_callback then
  luatexbase.add_to_callback("wrapup_run", write_sidecar, "wideband.sidecar")
end

return wideband
