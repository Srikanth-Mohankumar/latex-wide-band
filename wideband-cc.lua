-- wideband-cc.lua — Continuous-Column wide-band node surgery (throwaway POC).
--
-- Operations run in the output routine on the two finished \@makecol columns:
--   M.mark           write a position marker at the band's authored point in the flow
--   M.markpos        scan the finished columns for band markers (count + within-column
--                    heights) — drives page assignment and automatic Y
--   M.stripmarks     remove the placed bands' markers before the columns are recombined
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
local WHATSIT = N.id("whatsit")
local UD      = (N.subtype and N.subtype("user_defined")) or 8
local USER_ID = 0x57424E44                     -- "WBND"

local function zerokern() local k = N.new(KERN, 1); k.kern = 0; return k end

-- A band leaves this marker in the flow at the point it was authored. It has zero
-- height/depth, so it never affects layout; it rides with the surrounding text into
-- whichever page's column that authored position lands on, which is how the output
-- routine decides which page the band belongs to.
local function is_marker(n)
  return n.id == WHATSIT and n.subtype == UD and n.user_id == USER_ID
end

function M.mark()
  local w = N.new(WHATSIT, UD)
  w.user_id = USER_ID; w.type = 100; w.value = 0
  N.write(w)                                   -- append to the current (vertical) list
end

-- vertical walk: total at a node = TeX's \pagetotal there. Returns the list's full
-- accumulated height (total + trailing depth) so the caller can offset a second
-- column onto the same galley coordinate.
local function vscan(head, visit)
  local total, depth = 0, 0
  local n = head
  while n do
    if visit then visit(n, total) end
    local id = n.id
    if id == HLIST or id == VLIST or id == RULE then
      total = total + depth + (n.height or 0); depth = n.depth or 0
    elseif id == GLUE then total = total + depth + (n.width or 0); depth = 0
    elseif id == KERN then total = total + depth + (n.kern or 0); depth = 0 end
    n = n.next
  end
  return total + depth
end

-- Scan the two finished columns (boxes a, b) for band markers, in reading order:
-- all of column a top-to-bottom, then all of column b. Store the number found in
-- count register `kreg`, and each marker's GALLEY position (its \pagetotal, in sp,
-- measured in the recombined [col1|col2] galley) in the consecutive dimen registers
-- base, base+1, ... A column-1 marker's galley position is its within-column height;
-- a column-2 marker's is A_end + its within-column height, where A_end is column 1's
-- accumulated height — because joincols lays column 2 directly below column 1. The
-- i-th marker corresponds to the i-th pending band with a marker on this page (they
-- are emitted in document order). Non-destructive. `base` is \wbcc@mh@1's register.
function M.markpos(a, b, kreg, base)
  base = tonumber(base)
  local k = 0
  local ba = tex.box[tonumber(a)]
  local aend = (ba and ba.list) and vscan(ba.list, function(n, total)
    if is_marker(n) then tex.setdimen("global", base + k, total); k = k + 1 end
  end) or 0
  local bb = tex.box[tonumber(b)]
  if bb and bb.list then
    vscan(bb.list, function(n, total)
      if is_marker(n) then tex.setdimen("global", base + k, aend + total); k = k + 1 end
    end)
  end
  tex.setcount("global", tonumber(kreg), k)
end

-- Remove the first `n` markers (reading order: column a then b) from the two
-- finished columns. The caller passes n = every marker found on this page, so no
-- marker survives into the assembled page or the overflow: a band deferred off this
-- page is tracked by the output routine (\wbcc@overdue) and force-placed next page
-- from the pool, not by letting a marker ride forward. Call before joincols (which
-- would otherwise free a marker sitting at the column seam).
function M.stripmarks(a, b, n)
  n = tonumber(n)
  local removed = 0
  local function strip(num)
    local box = tex.box[tonumber(num)]
    if not (box and box.list) then return end
    local x = box.list
    while x and removed < n do
      local nx = x.next
      if is_marker(x) then
        local p = x.prev
        if p then p.next = nx else box.list = nx end
        if nx then nx.prev = p end
        x.next, x.prev = nil, nil; N.free(x); removed = removed + 1
      end
      x = nx
    end
  end
  strip(a); strip(b)
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
    tl.next = ch; ch.prev = tl        -- floats abut; \@makecol supplies their spacing
    local box = N.vpack(hb.list); hb.list = nil; tex.box[holdnum] = nil
    tex.setbox("global", holdnum, box)
  else
    local box = N.vpack(ch); if hb then hb.list = nil end; tex.box[holdnum] = nil
    tex.setbox("global", holdnum, box)
  end
  return cnt
end

-- Non-destructive measurement for the fit decision. Before the output routine
-- decides which bands fit this page it needs the footnote and bottom-float heights
-- that the real split will subtract from the budget — but it must not touch the
-- columns yet (if no band is placed they ship untouched). So: deep-copy each
-- finished column into a scratch box and run the REAL extraction on the copy, so
-- the hold boxes come out exactly as they will later. The caller reads their
-- dimensions and voids them; the copy is freed here.
function M.measurebottom(c1num, c2num, tmpnum, fnnum, bfLnum, bfRnum)
  local function probe(colnum, bfnum)
    local b = tex.box[colnum]
    if not (b and b.list) then return end
    tex.box[tmpnum] = nil
    tex.setbox("global", tmpnum, N.copy(b))       -- node.copy is deep (copies the list)
    M.takefootnotes(tmpnum, fnnum)
    M.takebotfloats(tmpnum, bfnum)
    tex.box[tmpnum] = nil                          -- free the copy
  end
  probe(c1num, bfLnum)
  probe(c2num, bfRnum)
end

return M
