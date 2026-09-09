-- wideband-cc.lua — Continuous-Column wide-band node surgery (throwaway POC).
--
-- Three operations, all run in the output routine on the two finished \@makecol
-- columns before they are recombined and re-split around the band:
--   M.joincols       recombine the columns with a correct interline glue at the join
--   M.takefootnotes  pull each column's footnote block out (re-set at the page bottom)
--   M.takebotfloats  pull each column's [b] bottom float out (re-set at the page bottom)
-- See wideband-cc.sty for how they fit together.
local M = {}
local N       = node
local KERN    = N.id("kern")
local GLUE    = N.id("glue")
local HLIST   = N.id("hlist")
local VLIST   = N.id("vlist")
local RULE    = N.id("rule")

local function zerokern() local k = N.new(KERN, 1); k.kern = 0; return k end

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
  -- take ownership of both lists (detach, then void the registers) so the stolen
  -- nodes are not double-freed
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

-- Bottom-float extraction. \@makecol places a column's bottom floats just above
-- its \@makecol tail, each as a VLIST (the float box) preceded by float-separation
-- glue. The rebuild's reduced budget would carry that column-bottom region into the
-- overflow (the float defers to the next page). This removes the trailing float
-- VLIST(s) and appends them to a hold box, so the caller can re-set them at the
-- band page's bottom. Call takefootnotes FIRST (footnotes sit below the floats),
-- so by here the floats are the column's trailing boxes. Returns the count kept.
function M.takebotfloats(colnum, holdnum)
  local b = tex.box[colnum]
  if not (b and b.list) then return 0 end
  -- find the last top-level text line; everything after it is trailing material
  -- (bottom floats + their separation glue + the \@makecol bottom tail).
  local lasttext
  local x = b.list
  while x do if x.id == HLIST then lasttext = x end; x = x.next end
  if not lasttext or not lasttext.next then return 0 end
  local trailing = lasttext.next
  lasttext.next = nil                 -- column now ends at its last text line
  trailing.prev = nil
  -- from the trailing material keep the float VLISTs; free glue/kern/tail
  local ch, ctl, cnt = nil, nil, 0
  local n = trailing
  while n do
    local nx = n.next
    n.next, n.prev = nil, nil
    if n.id == VLIST then
      cnt = cnt + 1
      if not ch then ch = n; ctl = n else ctl.next = n; n.prev = ctl; ctl = n end
    else
      N.free(n)
    end
    n = nx
  end
  if not ch then return 0 end
  local hb = tex.box[holdnum]
  if hb and hb.list then
    local tl = N.tail(hb.list)
    local g = N.new(GLUE); g.width = 6 * 65536; g.subtype = 0   -- \floatsep between floats
    tl.next = ch; ch.prev = tl                                  -- (kept simple; no glue node inserted)
    local box = N.vpack(hb.list); hb.list = nil; tex.box[holdnum] = nil
    tex.setbox("global", holdnum, box)
  else
    local box = N.vpack(ch); if hb then hb.list = nil end; tex.box[holdnum] = nil
    tex.setbox("global", holdnum, box)
  end
  return cnt
end

return M
