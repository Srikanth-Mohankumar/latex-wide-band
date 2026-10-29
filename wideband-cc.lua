-- wideband-cc.lua — Continuous-Column wide-band node surgery.
--
-- Operations run in the output routine on the two finished \@makecol columns:
--   M.mark           write a position marker at the band's authored point in the flow
--   M.markpos        scan the finished columns for band markers (count + within-column
--                    heights) — drives page assignment and automatic Y
--   M.stripmarks     remove the placed bands' markers before the columns are recombined
--   M.joincols       recombine the columns with a correct interline glue at the join
--   M.takefootnotes  pull each column's footnote block out (re-set at the page bottom)
--   M.takebotfloats  pull each column's [b] bottom float out (re-set at the page bottom)
--   M.takeinserts    detach the inserts (footnotes) trapped in the captured band box;
--   M.putinserts     ... and append them to the flow where the band is placed
--   M.fninit         tag each footnote with its callout as it reaches the page builder
--   M.fnmove         move a note whose callout went to the overflow back to its callout
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

-- A \footnote in the band body leaves an insert node inside the captured box (often
-- nested in an \hbox, e.g. an \fbox or a display). TeX migrates inserts only out of
-- paragraph lines, so a boxed one never reaches the page builder and the note is
-- lost. Detach every insert from the band box (recursively) and hold them; putinserts
-- appends them to the current vertical list, where the page builder sets them on the
-- page that list lands on. Host-neutral: whatever the class's \footnote expands to,
-- its result is an insert.
local INS = N.id("ins")
local held = nil
function M.takeinserts(boxnum)
  local b = tex.box[boxnum]
  if not b then return end
  local function walk(box)
    local x = box.list
    while x do
      local nx = x.next
      if x.id == INS then
        box.list = N.remove(box.list, x)
        x.next = nil; x.prev = nil
        if held then local t = N.tail(held); t.next = x; x.prev = t else held = x end
      elseif (x.id == HLIST or x.id == VLIST) and x.list then
        walk(x)
      end
      x = nx
    end
  end
  walk(b)
end
function M.putinserts()
  if held then N.write(held); held = nil end
end

-- A band page ships its row segments in VISUAL order (row 1 left, row 1 right, band,
-- row 2 left, ...) but the text runs in READING order (every left segment, then every
-- right one). A hyperlink broken across two segments would therefore be interleaved
-- with another segment's links, and the PDF backend's link stack unbalances ("endlink
-- used without startlink"). Kernel columns never meet this: they ship in reading order.
-- Make every segment self-contained: walk the segments (box registers, reading order),
-- close each link still open at a segment's last line and reopen a copy at the next
-- segment's first line. A link open from the previous page stays open into the first
-- segment, and one open at the end of the last segment runs on to the next page, as on
-- a kernel page. Only links at line level are tracked (an \href in running text).
local WHATSIT_ST = N.subtype and N.subtype("pdf_start_link")
local WHATSIT_EN = N.subtype and N.subtype("pdf_end_link")
local function lines_of(box)
  local first, last
  for x in N.traverse(box.list) do
    if x.id == HLIST and x.list then first = first or x; last = x end
  end
  return first, last
end
function M.balancelinks(...)
  if not (WHATSIT_ST and WHATSIT_EN) then return end
  local segs = {}
  for _, n in ipairs({...}) do
    local b = tex.box[n]
    if b and b.list then segs[#segs + 1] = b end
  end
  local open = {}                                   -- start-link nodes still open, outermost first
  for k, seg in ipairs(segs) do
    local first, last = lines_of(seg)
    if first and k > 1 and #open > 0 then           -- reopen what the previous segment carried;
      for i = #open, 1, -1 do                       -- the scan below pushes the copies again
        first.list = N.insert_before(first.list, first.list, N.copy(open[i]))
      end
      open = {}
    end
    for x in N.traverse(seg.list) do
      if x.id == HLIST and x.list then
        for y in N.traverse(x.list) do
          if y.id == WHATSIT and y.subtype == WHATSIT_ST then open[#open + 1] = y
          elseif y.id == WHATSIT and y.subtype == WHATSIT_EN and #open > 0 then open[#open] = nil end
        end
      end
    end
    if last and k < #segs and #open > 0 then        -- close them at this segment's last line
      for _ = 1, #open do
        N.insert_after(last.list, N.tail(last.list), N.new(WHATSIT, WHATSIT_EN))
      end
    end
  end
end

-- A column built after \enlargethispage: \@makecol's special column box is
--   \vbox to\@colht{ \vbox to H{content} \vss }      (H = \@colht + the enlargement)
-- one level deeper than a normal column, so every reader below would miss the
-- content (a band's marker was never found and the band never placed). Return the
-- box that holds the content -- the inner vlist for that exact two-node shape, else
-- the column itself.
local function colcontent(box)
  if not (box and box.list) then return box end
  local a = box.list
  local b = a.next
  if a.id == VLIST and b and b.id == GLUE and not b.next
     and b.width == 0 and b.stretch_order > 0 and b.shrink_order > 0 then
    return a
  end
  return box
end

-- The enlargement of column box `num` (inner height minus the column's), or nil for
-- a normal column.
local function colextra(num)
  local box = tex.box[tonumber(num)]
  local c = colcontent(box)
  if c == box then return nil end
  return c.height - box.height
end

-- \wbcc@enl := the page's enlargement for a rebuild: the larger of the two columns'
-- (\enlargethispage is per column in two-column mode; the operator asked for a taller
-- page, and a rebuilt page has one height for both columns). 0 when neither has one.
function M.enlargement(a, b, dreg)
  local ea, eb = colextra(a), colextra(b)
  local e = 0
  if ea and eb then e = math.max(ea, eb) else e = ea or eb or 0 end
  tex.setdimen("global", tonumber(dreg), e)
end

-- dimen `dreg` := how far the fuller of two finished columns prints past its own height
-- (natural height of its content minus the box height; <= 0 when it fits).
function M.overflow(a, b, dreg)
  local worst = -1073741823
  for _, num in ipairs({tonumber(a), tonumber(b)}) do
    local c = colcontent(tex.box[num])
    if c and c.list then
      local nat = N.vpack(N.copy_list(c.list))
      worst = math.max(worst, nat.height - c.height)
      N.flush_node(nat)
    end
  end
  tex.setdimen("global", tonumber(dreg), math.max(worst, -1073741823))
end

-- \wbcc@planned := the floats a NeoPage float plan (satellite.json, floatReorder) puts on
-- physical page `page`, comma-separated ("" without a loaded plan). A page of its own
-- for a band takes that page number from the plan; those floats are then never set.
-- The plan's early-page shift is applied as NeoPage applies it.
local plan
function M.planned(page)
  page = tonumber(page)
  local found = {}
  local sr = rawget(_G, "spacereserve")
  if type(sr) == "table" and sr.float_reorder_loaded and sr.loaded_float_reorder_file then
    if plan == nil then
      plan = false
      local f = io.open(sr.loaded_float_reorder_file, "r")
      local json = utilities and utilities.json
      if f and json then
        local ok, data = pcall(json.tolua, (f:read("*a"):gsub(",%s*([}%]])", "%1")))
        local order = ok and type(data) == "table" and data.floatReorder
          and data.floatReorder.floatPlacementOrder
        if type(order) == "table" then plan = order end
      end
      if f then f:close() end
    end
    local norm = sr.early_page_normalization or {}
    for _, e in ipairs(plan or {}) do
      local p = tonumber(e.page)
      if p and norm.active and tonumber(norm.shift_start_page)
        and (tonumber(norm.shift_amount) or 0) > 0 and p >= tonumber(norm.shift_start_page) then
        p = p + tonumber(norm.shift_amount)
      end
      if p == page then
        found[#found + 1] = tostring((e.floatMeta or {}).no or e.no or "?")
      end
    end
  end
  token.set_macro("wbcc@planned", table.concat(found, ", "), "global")
end

-- Replace a special column box by its content box, for a page that is rebuilt.
function M.unwrapcol(num)
  num = tonumber(num)
  local box = tex.box[num]
  local c = colcontent(box)
  if c == box then return end
  box.list = c.list; c.list = nil      -- the content moves up one level; the shell keeps
  box.height = c.height                -- the inner height, and is otherwise unchanged
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
-- Positions are stored in the dimen registers base .. base+maxn-1 only (the TeX side
-- allocates exactly maxn of them); every marker is still COUNTED. Without the bound a
-- page with more markers than registers wrote past the pool into whatever register was
-- allocated next (it clobbered a user setting once the pool stopped being the last
-- allocation).
function M.markpos(a, b, kreg, base, maxn)
  base = tonumber(base); maxn = tonumber(maxn) or math.huge
  local k = 0
  local function store(pos)
    if k < maxn then tex.setdimen("global", base + k, pos) end
    k = k + 1
  end
  local ba = colcontent(tex.box[tonumber(a)])
  local aend = (ba and ba.list) and vscan(ba.list, function(n, total)
    if is_marker(n) then store(total) end
  end) or 0
  local bb = colcontent(tex.box[tonumber(b)])
  if bb and bb.list then
    vscan(bb.list, function(n, total)
      if is_marker(n) then store(aend + total) end
    end)
  end
  tex.setcount("global", tonumber(kreg), k)
end

-- Remove the first `n` markers (reading order: column a then b) from the two
-- finished columns: the markers of the bands PLACED on this page (n = m) when the page
-- is rebuilt — the later markers lie in the overflow and ride to the next page — or
-- every marker found (n = found) when the page ships as it is. Call before joincols
-- (which would otherwise free a marker sitting at the column seam).
function M.stripmarks(a, b, n)
  n = tonumber(n)
  local removed = 0
  local function strip(num)
    local box = colcontent(tex.box[tonumber(num)])
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

-- Footnotes that ride to the next page. A rebuilt page holds less text than the page
-- TeX built, so a footnote's callout line can go to the overflow while its note, already
-- set in the column's footnote block, stays on this page (NeoPage JCLP_146437: note on
-- page 5, callout on page 6). TeX consumed the insert, so nothing ties a note to its
-- callout any more; tag them while they are still together. When an insert of class
-- \footins reaches the page builder, the note's top-level nodes get its id (they keep it
-- through \box\footins and \@makecol), a marker with the same id stays in the text where
-- the insert was (right after the callout's line), and a copy of the insert is kept.
local INS     = N.id("ins")
local FNATTR  = luatexbase.new_attribute("wbcc@fnid")
local FN_USER = USER_ID + 1
local fnclass, fnnext, fnstore = nil, 0, {}
local function tagnotes()
  local head = tex.lists.contrib_head
  local x = head
  while x do
    if x.id == INS and x.subtype == fnclass and not N.has_attribute(x, FNATTR) then
      fnnext = fnnext + 1
      local lines = 0
      for y in N.traverse(x.head) do
        N.set_attribute(y, FNATTR, fnnext)
        if y.id == HLIST or y.id == VLIST then lines = lines + 1 end
      end
      N.set_attribute(x, FNATTR, fnnext)
      fnstore[fnnext] = {ins = N.copy(x), lines = lines}
      local w = N.new(WHATSIT, UD)
      w.user_id = FN_USER; w.type = 100; w.value = fnnext
      head = N.insert_before(head, x, w)
    end
    x = x.next
  end
  tex.lists.contrib_head = head
end
function M.fninit(class)
  fnclass = tonumber(class)
  luatexbase.add_to_callback("buildpage_filter", tagnotes, "wideband-cc.footnotes")
end
-- After a rebuild: for every note marker in the overflow galley whose note is in the
-- hold box (all its lines; a note TeX itself split across pages is left alone), take
-- the note out of the hold box and put a copy of its insert back after the marker, so
-- the page builder sets it on the callout's page. count `creg` := notes moved.
function M.fnmove(galleynum, holdnum, creg)
  local moved = 0
  local g, hb = tex.box[tonumber(galleynum)], tex.box[tonumber(holdnum)]
  if g and g.list and hb and hb.list then
    local x = g.list
    while x do
      if x.id == WHATSIT and x.subtype == UD and x.user_id == FN_USER and fnstore[x.value] then
        local st, found = fnstore[x.value], {}
        local lines = 0
        for y in N.traverse(hb.list) do
          if N.has_attribute(y, FNATTR, x.value) then
            found[#found + 1] = y
            if y.id == HLIST or y.id == VLIST then lines = lines + 1 end
          end
        end
        if lines > 0 and lines == st.lines then
          for _, y in ipairs(found) do hb.list = N.remove(hb.list, y); N.flush_node(y) end
          g.list = N.insert_after(g.list, x, N.copy(st.ins))
          moved = moved + 1
        elseif lines > 0 then
          texio.write_nl("log", "wideband-cc: a footnote split across pages stays where TeX set it")
        end
      end
      x = x.next
    end
    if moved > 0 then
      -- the glue that separated the two columns' notes may now lead or trail the block
      while hb.list and hb.list.id == GLUE and not N.has_attribute(hb.list, FNATTR) do
        hb.list = N.remove(hb.list, hb.list)
      end
      local t = hb.list and N.tail(hb.list)
      while t and t.id == GLUE and not N.has_attribute(t, FNATTR) do
        hb.list = N.remove(hb.list, t); t = hb.list and N.tail(hb.list)
      end
      local list = hb.list; hb.list = nil
      tex.setbox("global", tonumber(holdnum), list and N.vpack(list) or nil)
    end
  end
  tex.setcount("global", tonumber(creg), moved)
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

-- Count the band markers at the top level of box boxnum (used on the overflow galley
-- after the split: those markers RIDE to the next page). Result -> count register kreg.
function M.countmarks(boxnum, kreg)
  local b = tex.box[boxnum]
  local n = 0
  if b and b.list then
    for x in N.traverse(b.list) do if is_marker(x) then n = n + 1 end end
  end
  tex.setcount("global", kreg, n)
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
    tex.setbox("global", tmpnum, N.copy(colcontent(b)))  -- deep copy of the content
    M.takefootnotes(tmpnum, fnnum)
    M.takebotfloats(tmpnum, bfnum)
    tex.box[tmpnum] = nil                          -- free the copy
  end
  probe(c1num, bfLnum)
  probe(c2num, bfRnum)
end

return M
