-- wideband-cc.lua — Continuous-Column POC node surgery (throwaway).
-- Reuses the vertical-position accounting and legal-breakpoint rules proven in
-- wideband.lua (stratum model), specialised to the CC assembly.
local M = {}
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
local USER_ID = 0x57424E44

local reg = {}
function M.setup(t) for k, v in pairs(t) do reg[k] = tonumber(v) end end
local function setcount(n, v) tex.setcount("global", reg[n], v) end
local function setdimen(n, v) tex.setdimen("global", reg[n], v) end

local function discardable(id)
  return id == GLUE or id == KERN or id == PENALTY or id == MATHN
end
local function maxdepth()
  local m = tex.maxdepth; if not m or m <= 0 then m = 4 * 65536 end; return m
end
local function zerokern() local k = N.new(KERN, 1); k.kern = 0; return k end
local function is_marker(n)
  return n.id == WHATSIT and n.subtype == UD and n.user_id == USER_ID
end

-- vertical walk: total at a node = TeX's \pagetotal there
local function vscan(head, md, visit)
  local total, depth = 0, 0
  local prev = nil
  local n = head
  while n do
    if visit then visit(n, total, prev) end
    local id = n.id
    if id == HLIST or id == VLIST or id == RULE then
      total = total + depth + (n.height or 0); depth = n.depth or 0
      if depth > md then total = total + depth - md; depth = md end
    elseif id == GLUE then total = total + depth + (n.width or 0); depth = 0
    elseif id == KERN then total = total + depth + (n.kern or 0); depth = 0 end
    prev = n; n = n.next
  end
  return total, depth
end

local function legal(n, prev)
  local id = n.id
  if id == GLUE then return prev ~= nil and not discardable(prev.id)
  elseif id == KERN then return n.next ~= nil and n.next.id == GLUE
  elseif id == PENALTY then return (n.penalty or 0) < 10000 end
  return false
end

function M.mark(id)
  local w = N.new(WHATSIT, UD)
  w.user_id = USER_ID; w.type = 100; w.value = tonumber(id) or 0
  N.write(w)
end

-- first marker of a box: found count, band id, vertical position h
function M.markinfo(boxnum)
  local b = tex.box[boxnum]
  local cnt, pos, bid = 0, 0, 0
  if b and b.list then
    vscan(b.list, maxdepth(), function(n, total)
      if is_marker(n) then cnt = cnt + 1; if cnt == 1 then pos = total; bid = n.value or 0 end end
    end)
  end
  setcount("found", cnt); setcount("bid", bid); setdimen("h", pos)
end

local function prune_trailing_discardables(head)
  if not head then return nil end
  local last = head
  while last.next do last = last.next end
  while last and discardable(last.id) do
    local pr = last.prev
    last.next, last.prev = nil, nil; N.free(last)
    if pr then pr.next = nil end
    last = pr
  end
  if not last then return nil end
  return head
end

-- Cut box `src` at its first marker. topreg <- everything strictly above the
-- marker; botreg <- everything after the marker and the reservation that
-- follows it (marker whatsit + following discardables = \nobreak penalty +
-- reservation kern + strays are dropped).
function M.cutmarker(src, topreg, botreg)
  local b = tex.box[src]
  if not (b and b.list) then setcount("found", 0); return end
  local head = b.list; b.list = nil; tex.box[src] = nil
  local mk = head
  while mk and not is_marker(mk) do mk = mk.next end
  if not mk then
    tex.setbox("global", topreg, N.vpack(head))
    tex.setbox("global", botreg, N.vpack(zerokern()))
    setcount("found", 0); return
  end
  local tophead = head
  local p = mk.prev
  if p then p.next = nil; mk.prev = nil else tophead = nil end
  tophead = prune_trailing_discardables(tophead)
  -- after the marker: free marker, then drop the reservation (discardables)
  local rest = mk.next
  mk.next, mk.prev = nil, nil; N.free(mk)
  while rest and discardable(rest.id) do
    local nxt = rest.next; rest.next, rest.prev = nil, nil; N.free(rest); rest = nxt
  end
  if rest then rest.prev = nil end
  local topbox = N.vpack(tophead or zerokern())
  local botbox = N.vpack(rest or zerokern())
  tex.setbox("global", topreg, topbox)
  tex.setbox("global", botreg, botbox)
  setdimen("topnat", topbox.height); setdimen("botnat", botbox.height)
  setcount("found", 1)
end

local function find_break(head, ymin)
  local best, bp = nil, 0
  vscan(head, maxdepth(), function(n, total, prev)
    if best == nil and total >= ymin and legal(n, prev) then best, bp = n, total end
  end)
  return best, bp
end

-- Split box `src` at first legal breakpoint at/after height y.
function M.splitat(src, y, topreg, botreg)
  y = tonumber(y)
  local b = tex.box[src]
  if not (b and b.list) then setcount("found", 0); return end
  local head = b.list; b.list = nil; tex.box[src] = nil
  local best = find_break(head, y)
  if not best then
    tex.setbox("global", topreg, N.vpack(head))
    tex.setbox("global", botreg, N.vpack(zerokern()))
    setcount("found", 0); return
  end
  local tophead = head
  local p = best.prev
  if p then p.next = nil; best.prev = nil else tophead = nil end
  local rest = best
  while rest and discardable(rest.id) do
    local nxt = rest.next; rest.next, rest.prev = nil, nil; N.free(rest); rest = nxt
  end
  if rest then rest.prev = nil end
  local tb = N.vpack(tophead or zerokern())
  local bb = N.vpack(rest or zerokern())
  tex.setbox("global", topreg, tb)
  tex.setbox("global", botreg, bb)
  setdimen("topnat", tb.height); setdimen("botnat", bb.height)
  setcount("found", 1)
end

-- Concatenate the two finished columns into the galley with a correct interline
-- glue at the join. \@makecol left column 1 with a bottom tail (\vskip-\dp then
-- an infinite-stretch \@textbottom) and column 2 with a leading \topskip; both
-- are wrong mid-galley. Drop them and splice the glue TeX itself would put
-- between column 1's last line and column 2's first line: baselineskip minus the
-- prevdepth and height, else lineskip. bs/ls/limit are widths in sp (standard
-- baselineskip is rigid, so the width is exact).
function M.joincols(dstnum, c1num, c2num, bs, ls, limit)
  bs, ls, limit = tonumber(bs), tonumber(ls), tonumber(limit)
  local c1, c2 = tex.box[c1num], tex.box[c2num]
  local l1 = c1 and c1.list
  local l2 = c2 and c2.list
  -- take ownership of both lists (detach, then void the registers, as
  -- cutmarker/splitat do) so the stolen nodes are not double-freed
  if c1 then c1.list = nil; tex.box[c1num] = nil end
  if c2 then c2.list = nil; tex.box[c2num] = nil end
  local function isbox(n) return n and (n.id == HLIST or n.id == VLIST or n.id == RULE) end
  local t = l1 and N.tail(l1)
  while t and not isbox(t) do              -- drop column 1's \@makecol bottom tail
    local p = t.prev
    if p then p.next = nil else l1 = nil end
    t.prev = nil; N.free(t); t = p
  end
  while l2 and not isbox(l2) do            -- drop column 2's leading \topskip
    local nx = l2.next
    if nx then nx.prev = nil end
    l2.next = nil; N.free(l2); l2 = nx
  end
  if not (t and l2) then                   -- a column collapsed: just join what is left
    local box = N.vpack(l1 or l2 or zerokern())  -- capture: vpack also returns badness
    tex.setbox("global", dstnum, box)
    return
  end
  local g = N.new(GLUE)
  local w = bs - (t.depth or 0) - (l2.height or 0)
  if w < limit then g.width = ls; g.subtype = 1   -- lineskip
  else g.width = w; g.subtype = 2 end             -- baselineskip
  t.next = g; g.prev = t; g.next = l2; l2.prev = g
  local box = N.vpack(l1)                    -- capture the node only (vpack also returns badness)
  tex.setbox("global", dstnum, box)
end

-- Footnote extraction for the in-run rebuild. \@makecol bakes each finished
-- column's footnotes at its bottom as: [\skip\footins glue][colour push]
-- [kern -3][\footnoterule][kern 2.6][footnote boxes][colour pop] + the \@makecol
-- bottom tail. Splitting such a column scatters those footnotes mid-page. This
-- removes that apparatus from a column and appends the footnote *content* (the
-- boxes below the rule, with their interline glue) to a hold box, so the caller
-- can set one clean footnote block at the true page bottom. Returns nothing; the
-- column keeps its text (+ \@makecol tail, which joincols strips later).
local function apparatus_start(rule, isbox)   -- first non-box node before the rule
  local p = rule
  while p.prev and not isbox(p.prev) do p = p.prev end
  return p
end
function M.takefootnotes(colnum, holdnum)
  local b = tex.box[colnum]
  if not (b and b.list) then return end
  local function isbox(n) return n and (n.id == HLIST or n.id == VLIST) end
  -- locate the footnote rule: the last rule narrower than the column
  local rule
  local x = b.list
  while x do
    if x.id == RULE and x.width and x.width > 0 and x.width < 0.7 * (b.width or 0) then rule = x end
    x = x.next
  end
  if not rule then return end
  local startp = apparatus_start(rule, isbox)          -- \skip\footins glue
  -- \@makecol tail = first sub=0 glue of negative width after the rule
  local tail = rule.next
  while tail do
    if tail.id == GLUE and (tail.subtype or 0) == 0 and (tail.width or 0) < 0 then break end
    tail = tail.next
  end
  local blockend = tail and tail.prev or N.tail(b.list)
  -- excise the apparatus [startp .. blockend] from the column
  local before = startp.prev
  if before then before.next = tail else b.list = tail end
  if tail then tail.prev = before end
  if startp then startp.prev = nil end
  if blockend then blockend.next = nil end
  -- from the excised block keep boxes + interline glue (sub=2/1); drop the rule,
  -- kerns, \skip\footins glue and the colour-stack whatsits (as a balanced pair)
  local ch, ctl
  local n = startp
  while n do
    local nx = n.next
    n.next, n.prev = nil, nil
    local keep = isbox(n) or (n.id == GLUE and (n.subtype == 2 or n.subtype == 1) and ch)
    if keep and n ~= rule then
      if not ch then ch = n; ctl = n else ctl.next = n; n.prev = ctl; ctl = n end
    else
      N.free(n)
    end
    n = nx
  end
  if not ch then return end
  -- append to the hold box (with a baselineskip between a previous block and this)
  local hb = tex.box[holdnum]
  if hb and hb.list then
    local t = N.tail(hb.list)
    local g = N.new(GLUE); g.width = 6*65536; g.subtype = 0   -- \skip\footins between columns' notes
    t.next = g; g.prev = t; g.next = ch; ch.prev = g
    local box = N.vpack(hb.list); hb.list = nil; tex.box[holdnum] = nil
    tex.setbox("global", holdnum, box)
  else
    local box = N.vpack(ch); if hb then hb.list = nil end; tex.box[holdnum] = nil
    tex.setbox("global", holdnum, box)
  end
end

return M
