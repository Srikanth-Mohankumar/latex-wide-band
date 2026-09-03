-- wideband-audit.lua -- material ledger for two-column LuaLaTeX documents
--
-- Node-level half of wideband-audit.sty.  It never modifies the shipped
-- page: the only writes it performs are attribute assignments made before
-- shipout (attributes carry no typographic meaning) and log lines.
--
-- Everything the module remembers lives in the single table M.state.
--
-- Interface used by wideband-audit.sty
--   setup{...}        register numbers and options
--   line_filter(head) post_linebreak_filter: hand out line sequence ids
--   display()         \everydisplay: hand out a display sequence id
--   page_setup{...}   build/page/before: per-page geometry + frame tag
--   shipout(box)      pre_shipout_filter: walk the page and run the checks
--   finish()          wrapup_run: document-level checks, summary, sidecar
--   patch(name, ok)   record whether a kernel patch applied
--
-- Interface used by the wideband core (contract section 5.2)
--   request(bandid)   record the current highest sequence id for a band

local M = {}

local HLIST   = node.id("hlist")
local VLIST   = node.id("vlist")
local RULE    = node.id("rule")
local GLUE    = node.id("glue")
local KERN    = node.id("kern")
local GLYPH   = node.id("glyph")
local MATH    = node.id("math")
local RUNNING = -1073741824          -- "running" rule dimension
local SP      = 65536.0              -- scaled points per point
local TOL     = 32768                -- 0.5pt in sp
local RULERTOL = 64                  -- self check slack, in sp
local DISC    = node.id("disc")

-- kind values (contract section 5.2)
local KIND_BODY, KIND_FLOAT, KIND_FOOT, KIND_MARGIN, KIND_HEADFOOT = 0, 1, 2, 3, 4

local S = {
  -- configuration ---------------------------------------------------------
  attr      = {},              -- attribute register numbers
  opts      = { json = true, verbose = false },
  bandattr  = nil,             -- CORE's wb@attr@band, resolved lazily
  bandattr_done = false,
  ba        = nil,             -- cached copy for the walk
  -- creation-time bookkeeping ---------------------------------------------
  seq       = 0,               -- highest sequence id handed out
  created   = 0,               -- ids handed out
  mustship  = {},              -- seq -> true when the id was created on the
                               -- main vertical list (it must be shipped)
  isdisplay = {},              -- seq -> true for display-math ids
  -- shipout-time bookkeeping ----------------------------------------------
  page      = 0,               -- pages shipped
  shipped   = {},              -- seq -> number of ledger entries
  seqpages  = {},              -- seq -> first page it was shipped on
  prevlast  = nil,             -- last body id of the previous page
  prevpage  = nil,
  pages     = {},              -- per page record (sidecar)
  bands     = {},              -- band id -> record
  fn        = {},              -- footnote id -> {mark=..., texts={...}}
  -- results ---------------------------------------------------------------
  fails     = 0,
  nfoot     = 0,
  patches   = {},              -- name -> true/false
  skips     = {},              -- check -> reason
  faillines = {},              -- for the sidecar
  pageinfo  = nil,             -- geometry of the page being shipped
}
M.state = S

----------------------------------------------------------------------
-- logging
----------------------------------------------------------------------

-- TeX breaks log lines at max_print_line (79 columns) and the next writer
-- continues on our line, so keep every record short and terminate it.
local function logline(s)
  if #s > 78 then s = s:sub(1, 78) end
  texio.write_nl("log", s)
  texio.write_nl("log", "")
end

local function pt(sp)
  return string.format("%.2fpt", sp / SP)
end

local function ok(check, detail)
  logline("WBAUDIT: " .. check .. " ok " .. detail)
end

local function fail(check, detail)
  S.fails = S.fails + 1
  local line = "WBAUDIT: " .. check .. " FAIL " .. detail
  S.faillines[#S.faillines + 1] = line
  logline(line)
end

local function skip(check, reason)
  S.skips[check] = reason
  logline("WBAUDIT: " .. check .. " skipped " .. reason)
end

local function info(s)
  if S.opts.verbose then logline("WBAUDIT INFO: " .. s) end
end

----------------------------------------------------------------------
-- setup
----------------------------------------------------------------------

function M.setup(t)
  t = t or {}
  S.attr.seq   = luatexbase.registernumber("wbaudit@attr@seq")
  S.attr.kind  = luatexbase.registernumber("wbaudit@attr@kind")
  S.attr.fn    = luatexbase.registernumber("wbaudit@attr@fn")
  S.attr.frame = luatexbase.registernumber("wbaudit@attr@frame")
  for _, k in ipairs { "seq", "kind", "fn", "frame" } do
    if not S.attr[k] then
      error("wideband-audit: attribute wbaudit@attr@" .. k .. " is not defined")
    end
  end
  if t.json ~= nil then S.opts.json = t.json end
  if t.verbose ~= nil then S.opts.verbose = t.verbose end
end

-- CORE's band attribute is looked up on first use so that the load order of
-- wideband and wideband-audit does not matter.  A missing attribute means
-- "this document has no bands" (contract section 5.2).
local function bandattr()
  if not S.bandattr_done then
    S.bandattr_done = true
    local n = luatexbase.registernumber("wb@attr@band")
    S.bandattr = (type(n) == "number") and n or nil
    info("band attribute " .. (S.bandattr and ("= " .. S.bandattr) or "absent"))
  end
  return S.bandattr
end

function M.patch(name, applied)
  S.patches[name] = (applied == true or applied == 1)
end

-- true when the \meaning of a macro shows no parameter text, i.e. when
-- \g@addto@macro is safe on it.  (Kept in Lua because a percent sign cannot
-- appear in the TeX source of a \directlua argument.)
function M.noparams(meaning)
  return meaning:match("^macro:%->") ~= nil
end

-- name of the first patch a check depends on that did not apply
local function patch_missing(a, b)
  if S.patches[a] == false then return a end
  if b and S.patches[b] == false then return b end
  return nil
end

----------------------------------------------------------------------
-- sequence ids
----------------------------------------------------------------------

-- true when the list the paragraph or display is contributed to is the main
-- vertical list.  Only such material is required to reach a page: anything
-- built inside a box may legitimately be discarded (the kernel typesets both
-- variants of a two-sided \marginpar, amsmath measures alignments, \sbox and
-- friends throw material away).
local function main_vertical(ptr)
  local lvl = tex.nest[ptr]
  return (lvl ~= nil) and (lvl.mode == 1)
end

function M.line_filter(head)
  local main = main_vertical(tex.nest.ptr)
  for n in node.traverse_id(HLIST, head) do
    S.seq = S.seq + 1
    S.created = S.created + 1
    node.set_attribute(n, S.attr.seq, S.seq)
    if main then S.mustship[S.seq] = true end
  end
  return head
end

-- called from \everydisplay; the display's own nest level is the top one, so
-- the list it will be contributed to is one level below.
function M.display()
  S.seq = S.seq + 1
  S.created = S.created + 1
  S.isdisplay[S.seq] = true
  if main_vertical(tex.nest.ptr - 1) then S.mustship[S.seq] = true end
  tex.setattribute(S.attr.seq, S.seq)
end

function M.request(bandid)
  bandid = tonumber(bandid)
  if not bandid then return end
  local b = S.bands[bandid]
  if not b then
    b = { id = bandid, count = 0 }
    S.bands[bandid] = b
  end
  b.req = S.seq
  info("band " .. bandid .. " requested after seq " .. S.seq)
end

----------------------------------------------------------------------
-- per page geometry
----------------------------------------------------------------------

-- Called from the build/page/before hook, i.e. before \@outputpage boxes
-- \@outputbox.  The text area is expressed in the coordinate system of the
-- shipout box (origin at its top left corner), so the 1in origin and
-- \hoffset/\voffset cancel out.  \@outputbox is tagged so that the walk can
-- prefer its measured position over the computed one.
function M.page_setup(t)
  S.pageinfo = {
    twocolumn = (tonumber(t.twocolumn) or 0) ~= 0,
    left      = tonumber(t.margin)     or 0,
    top       = (tonumber(t.topmargin) or 0) + (tonumber(t.headheight) or 0)
                + (tonumber(t.headsep) or 0),
    width     = tonumber(t.textwidth)  or 0,
    height    = tonumber(t.textheight) or 0,
    maxdepth  = tonumber(t.maxdepth)   or 0,
    counter   = tonumber(t.page)       or 0,
  }
  local b = tonumber(t.box)
  if b then
    local box = tex.box[b]
    if box then node.set_attribute(box, S.attr.frame, 1) end
  end
end

----------------------------------------------------------------------
-- the walk
----------------------------------------------------------------------

-- TeX rounds a set glue's contribution from the *cumulative* stretch or
-- shrink of the box (hlist_out/vlist_out keep cur_glue and cur_g), so the
-- walk does the same and lands on exactly the positions the PDF shows.
local function iround(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return -math.floor(-v + 0.5)
end

-- glue state of the box currently being walked
local function newglue(box)
  return { sign = box.glue_sign, order = box.glue_order, set = box.glue_set,
           cur = 0, g = 0 }
end

local function glue_width(n, gs)
  local w = n.width
  if gs.sign == 1 and n.stretch_order == gs.order then
    gs.cur = gs.cur + n.stretch
    local ng = iround(gs.set * gs.cur)
    w = w + ng - gs.g
    gs.g = ng
  elseif gs.sign == 2 and n.shrink_order == gs.order then
    gs.cur = gs.cur + n.shrink
    local ng = iround(gs.set * gs.cur)
    w = w - (ng - gs.g)
    gs.g = ng
  end
  return w
end

local walk_box                       -- forward declaration

-- ink accumulator: the bounding box of every glyph and rule that belongs to
-- the text area (kinds body, float and footnote).
local function record_ink(pg, x, ytop, w, h, d, kind, seq)
  pg.ink = pg.ink + 1
  if kind == KIND_MARGIN or kind == KIND_HEADFOOT then return end
  local a = pg.acc
  if not a.n then
    a.n, a.x0, a.x1, a.y0, a.y1, a.b1 = 0, x, x + w, ytop, ytop + h + d, ytop + h
    a.sx0, a.sx1, a.sy0, a.sy1, a.sb1 = seq, seq, seq, seq, seq
  end
  a.n = a.n + 1
  if x < a.x0 then a.x0 = x; a.sx0 = seq end
  if x + w > a.x1 then a.x1 = x + w; a.sx1 = seq end
  if ytop < a.y0 then a.y0 = ytop; a.sy0 = seq end
  if ytop + h + d > a.y1 then a.y1 = ytop + h + d; a.sy1 = seq end
  if ytop + h > a.b1 then a.b1 = ytop + h; a.sb1 = seq end
end

local function record_band(pg, band, x, w)
  local r = pg.bands[band]
  if not r then
    r = { x0 = x, x1 = x + w, at = pg.nentries }
    pg.bands[band] = r
  end
  if x < r.x0 then r.x0 = x end
  if x + w > r.x1 then r.x1 = x + w end
end

-- Kinds and band ids are read from every node, never inherited from an
-- enclosing box: LuaTeX gives a node the attributes that were in force when
-- it was created, so a glyph in the running head carries kind 4, while the
-- page box around it carries kind 4 too without that saying anything about
-- the column material nested deeper inside it.
local walk_hitems

-- walk the items of a horizontal list, returning the x reached.  hbox and
-- discretionary "replace" lists share the enclosing box's glue state, so
-- the same function serves both.
walk_hitems = function(n, pg, x, base, ctx, gs, boxh, boxd, depth)
  local KA, BA = S.attr.kind, S.ba
  while n do
    local id = n.id
    if id == GLYPH then
      local gx = x + (n.xoffset or 0)
      local gy = base - (n.yoffset or 0) - n.height
      record_ink(pg, gx, gy, n.width, n.height, n.depth,
        node.get_attribute(n, KA) or KIND_BODY, ctx.seq)
      if BA then
        local bd = node.get_attribute(n, BA)
        if bd then record_band(pg, bd, gx, n.width) end
      end
      x = x + n.width
    elseif id == HLIST or id == VLIST then
      walk_box(n, pg, x, base - n.height + n.shift, ctx)
      x = x + n.width
    elseif id == GLUE then
      x = x + glue_width(n, gs)
    elseif id == KERN then
      x = x + n.kern
    elseif id == RULE then
      -- a running dimension takes the value of the enclosing box
      local w  = (n.width  == RUNNING) and 0 or n.width
      local hh = (n.height == RUNNING) and boxh or n.height
      local dd = (n.depth  == RUNNING) and boxd or n.depth
      record_ink(pg, x, base - hh, w, hh, dd,
        node.get_attribute(n, KA) or KIND_BODY, ctx.seq)
      if BA then
        local bd = node.get_attribute(n, BA)
        if bd then record_band(pg, bd, x, w) end
      end
      x = x + w
    elseif id == DISC then
      -- an unbroken discretionary typesets its replace list inline; it
      -- often holds the kern that the hyphenation point removed
      if n.replace and depth < 8 then
        x = walk_hitems(n.replace, pg, x, base, ctx, gs, boxh, boxd, depth + 1)
      end
    elseif id == MATH then
      x = x + (n.surround or 0)
    end
    n = n.next
  end
  return x
end

local function walk_hlist(h, pg, x0, ytop, ctx)
  local base = ytop + h.height
  local gs = newglue(h)
  local x = walk_hitems(h.list, pg, x0, base, ctx, gs, h.height, h.depth, 0)
  -- self check: LuaTeX measures the same list in C, so a disagreement means
  -- the walk mis-handles a node type and the positions cannot be trusted
  if h.list then
    local ref = node.dimensions(h.glue_set, h.glue_sign, h.glue_order, h.list)
    local d = (x - x0) - ref
    if d > RULERTOL or d < -RULERTOL then
      pg.ruler = pg.ruler + 1
      if math.abs(d) > math.abs(pg.rulerworst) then pg.rulerworst = d end
    end
  end
end

local function walk_vlist(v, pg, x0, ytop, ctx)
  local y = ytop
  local gs = newglue(v)
  local KA, BA = S.attr.kind, S.ba
  local n = v.list
  while n do
    local id = n.id
    if id == HLIST or id == VLIST then
      walk_box(n, pg, x0 + n.shift, y, ctx)
      y = y + n.height + n.depth
    elseif id == GLUE then
      y = y + glue_width(n, gs)
    elseif id == KERN then
      y = y + n.kern
    elseif id == RULE then
      local hh = (n.height == RUNNING) and 0 or n.height
      local dd = (n.depth  == RUNNING) and 0 or n.depth
      local w  = (n.width  == RUNNING) and v.width or n.width
      record_ink(pg, x0, y, w, hh, dd,
        node.get_attribute(n, KA) or KIND_BODY, ctx.seq)
      if BA then
        local bd = node.get_attribute(n, BA)
        if bd then record_band(pg, bd, x0, w) end
      end
      y = y + hh + dd
    end
    n = n.next
  end
end

-- visit one box: read its attributes, record a ledger entry for the
-- outermost box that carries a sequence id, then descend.
walk_box = function(b, pg, x, ytop, ctx)
  local kind = node.get_attribute(b, S.attr.kind) or KIND_BODY
  local band = S.ba and node.get_attribute(b, S.ba) or nil
  local newseq = nil

  if not ctx.inseq then
    newseq = node.get_attribute(b, S.attr.seq)
    if newseq then
      pg.nentries = pg.nentries + 1
      pg.entries[pg.nentries] = {
        seq = newseq, kind = kind, idx = pg.nentries,
        x = x, y = ytop, w = b.width, h = b.height + b.depth,
      }
      S.shipped[newseq] = (S.shipped[newseq] or 0) + 1
      if not S.seqpages[newseq] then S.seqpages[newseq] = pg.num end
    end
  end
  local fnid = node.get_attribute(b, S.attr.fn)
  if fnid then
    local rec = S.fn[fnid]
    if not rec then rec = { texts = {} }; S.fn[fnid] = rec end
    if kind == KIND_FOOT then
      if not rec.texts[pg.num] then
        rec.texts[pg.num] = { page = pg.num, x = x }
        if not rec.firsttext then rec.firsttext = pg.num end
      end
    elseif not rec.mark then
      rec.mark = { page = pg.num, x = x }
    end
  end
  if node.get_attribute(b, S.attr.frame) then
    pg.frame = { x = x, y = ytop, w = b.width, h = b.height + b.depth }
  end
  if band then
    local r = S.bands[band]
    if not r then r = { id = band, count = 0 }; S.bands[band] = r end
    if not r.page then
      r.page = pg.num
      r.at   = pg.nentries
      r.count = r.count + 1
    elseif r.page ~= pg.num then
      r.count = r.count + 1
      r.extrapage = pg.num
    end
  end

  local nctx = ctx
  if newseq ~= nil then
    nctx = { seq = newseq, inseq = true }
  end
  if b.id == HLIST then
    walk_hlist(b, pg, x, ytop, nctx)
  else
    walk_vlist(b, pg, x, ytop, nctx)
  end
end

----------------------------------------------------------------------
-- per page checks
----------------------------------------------------------------------

local function body_entries(pg)
  local out, n = {}, 0
  for i = 1, pg.nentries do
    local e = pg.entries[i]
    local k = e.kind or KIND_BODY
    if S.mustship[e.seq] and k == KIND_BODY then
      -- a display can be spread over several sibling boxes (align rows);
      -- collapse adjacent repetitions of the same display id
      if not (n > 0 and out[n].seq == e.seq and S.isdisplay[e.seq]) then
        n = n + 1
        out[n] = e
      end
    end
  end
  return out, n
end

local function check_ledger_order(pg)
  local body, n = body_entries(pg)
  local bad, first = 0, nil
  local prev = nil
  for i = 1, n do
    local e = body[i]
    if prev and e.seq <= prev.seq then
      bad = bad + 1
      if not first then first = { at = e.idx, seq = e.seq, prev = prev.seq } end
    end
    prev = e
  end
  -- the last body id of the previous page must precede the first of this one
  if n > 0 and S.prevlast and body[1].seq <= S.prevlast then
    bad = bad + 1
    if not first then
      first = { at = body[1].idx, seq = body[1].seq, prev = S.prevlast }
    end
  end
  if bad == 0 then
    ok("ledger-order", "page=" .. pg.num .. " body=" .. n
       .. " first=" .. (n > 0 and body[1].seq or 0)
       .. " last=" .. (n > 0 and body[n].seq or 0))
  else
    fail("ledger-order", "page=" .. pg.num .. " bad=" .. bad
       .. " at=" .. first.at .. " seq=" .. first.seq .. " prev=" .. first.prev)
  end
  if n > 0 then S.prevlast = body[n].seq end
  pg.body = n
  return n
end

local function check_geometry_textarea(pg)
  local g = S.pageinfo
  if not g or g.height == 0 then
    skip("geometry-textarea", "page=" .. pg.num .. " no-geometry")
    return
  end
  -- marginal notes sit outside the text area by design and the running head
  -- and foot are excluded by the contract, so both must be identifiable
  local miss = patch_missing("marginparreset", "headfoot")
  if miss then
    skip("geometry-textarea", "page=" .. pg.num .. " patch-" .. miss)
    return
  end
  local a = pg.acc
  if not a.n then
    ok("geometry-textarea", "page=" .. pg.num .. " ink=0")
    return
  end
  local left = (pg.frame and pg.frame.x) or g.left
  local top  = (pg.frame and pg.frame.y) or g.top
  local right, bottom = left + g.width, top + g.height
  local worst, edge, seq = 0, nil, nil
  local function note(over, e, s)
    if over > worst then worst, edge, seq = over, e, s end
  end
  note(left - a.x0 - TOL, "left", a.sx0)
  note(a.x1 - right - TOL, "right", a.sx1)
  note(top - a.y0 - TOL, "top", a.sy0)
  -- the kernel puts the last baseline of a full column on the text area
  -- bottom, so ink may descend by up to \maxdepth below it
  note(a.y1 - bottom - g.maxdepth - TOL, "bottom-ink", a.sy1)
  note(a.b1 - bottom - TOL, "bottom", a.sb1)
  info("p" .. pg.num .. " rect " .. pt(left) .. " " .. pt(top) .. " "
    .. pt(right) .. " " .. pt(bottom) .. (pg.frame and " measured" or " computed"))
  info("p" .. pg.num .. " ink " .. pt(a.x0) .. " " .. pt(a.y0) .. " "
    .. pt(a.x1) .. " " .. pt(a.y1) .. " base " .. pt(a.b1))
  if pg.ruler > 0 then
    -- the walk could not reproduce LuaTeX's own measurement of some box, so
    -- no placement claim about this page would be trustworthy
    fail("geometry-textarea", "page=" .. pg.num .. " edge=ruler boxes="
      .. pg.ruler .. " by=" .. pt(pg.rulerworst))
  elseif worst <= 0 then
    ok("geometry-textarea", "page=" .. pg.num .. " ink=" .. pg.ink)
  else
    fail("geometry-textarea", "page=" .. pg.num .. " edge=" .. edge
      .. " by=" .. pt(worst) .. " seq=" .. tostring(seq))
  end
  pg.rect = { left = left, top = top, right = right, bottom = bottom }
end

local function column_of(x, pg)
  local g = S.pageinfo
  if not g or not g.twocolumn then return 0 end
  local left = (pg and pg.frame and pg.frame.x) or g.left
  return (x < left + g.width / 2) and 1 or 2
end

local function check_footnote_place(pg)
  local miss = patch_missing("footnotemark", "footnotetext")
  if miss then
    skip("footnote-place", "page=" .. pg.num .. " patch-" .. miss)
    return
  end
  local nfn, bad, first = 0, 0, nil
  for id, rec in pairs(S.fn) do
    local t = rec.texts[pg.num]
    if t then
      nfn = nfn + 1
      local m = rec.mark
      if not m then
        if not rec.reported then
          rec.reported = true
          info("footnote " .. id .. " has text but no mark")
        end
      elseif rec.firsttext == pg.num then
        local mc, tc = column_of(m.x, pg), column_of(t.x, pg)
        if m.page ~= pg.num or mc ~= tc then
          bad = bad + 1
          if not first then
            first = { id = id, mp = m.page, mc = mc, tp = pg.num, tc = tc }
          end
        end
      end
    end
  end
  if bad == 0 then
    ok("footnote-place", "page=" .. pg.num .. " fn=" .. nfn)
  else
    fail("footnote-place", "page=" .. pg.num .. " bad=" .. bad
      .. " fn=" .. first.id .. " mark=p" .. first.mp .. "c" .. first.mc
      .. " text=p" .. first.tp .. "c" .. first.tc)
  end
end

function M.shipout(box)
  if not box or (box.id ~= VLIST and box.id ~= HLIST) then return true end
  if S.finished then S.latepage = true end
  S.page = S.page + 1
  local pg = {
    num = S.page, entries = {}, nentries = 0, ink = 0,
    acc = {}, bands = {}, ruler = 0, rulerworst = 0,
    counter = S.pageinfo and S.pageinfo.counter,
  }
  S.ba = bandattr()
  walk_box(box, pg, 0, 0, { seq = nil, inseq = false })
  info("page " .. pg.num .. " entries=" .. pg.nentries
    .. " created=" .. S.created)
  check_ledger_order(pg)
  check_geometry_textarea(pg)
  check_footnote_place(pg)
  for band, r in pairs(pg.bands) do
    local b = S.bands[band]
    if b then
      b.x0 = math.min(b.x0 or r.x0, r.x0)
      b.x1 = math.max(b.x1 or r.x1, r.x1)
    end
  end
  S.pages[#S.pages + 1] = pg
  return true
end

----------------------------------------------------------------------
-- document level checks
----------------------------------------------------------------------

local function check_ledger_unique()
  local shipped, dup, lost = 0, 0, 0
  local firstdup, firstlost = nil, nil
  for seq, count in pairs(S.shipped) do
    shipped = shipped + 1
    if count > 1 and not S.isdisplay[seq] then
      dup = dup + 1
      if not firstdup or seq < firstdup then firstdup = seq end
    end
  end
  -- a display id may legitimately sit on several sibling boxes of one page
  -- (alignment rows); it is a duplicate only when it reaches two pages
  for seq in pairs(S.isdisplay) do
    local pages = {}
    local n = 0
    for _, pg in ipairs(S.pages) do
      for i = 1, pg.nentries do
        if pg.entries[i].seq == seq and not pages[pg.num] then
          pages[pg.num] = true; n = n + 1
        end
      end
    end
    if n > 1 then
      dup = dup + 1
      if not firstdup or seq < firstdup then firstdup = seq end
    end
  end
  for seq in pairs(S.mustship) do
    if not S.shipped[seq] then
      lost = lost + 1
      if not firstlost or seq < firstlost then firstlost = seq end
    end
  end
  local detail = "created=" .. S.created .. " shipped=" .. shipped
  if dup == 0 and lost == 0 then
    ok("ledger-unique", detail .. " dup=0 lost=0")
  else
    fail("ledger-unique", detail .. " dup=" .. dup .. " lost=" .. lost
      .. " first=" .. tostring(firstdup or firstlost))
  end
  return shipped
end

local function check_band_order()
  local nbands = 0
  for _ in pairs(S.bands) do nbands = nbands + 1 end
  if nbands == 0 then
    ok("band-order", "bands=0")
    return 0
  end
  local bad, first = 0, nil
  for id, b in pairs(S.bands) do
    if b.count and b.count > 1 then
      bad = bad + 1
      if not first then first = { id = id, why = "shipped=" .. b.count } end
    end
    if b.req and not b.page then
      bad = bad + 1
      if not first then first = { id = id, why = "never-shipped" } end
    end
    if b.req and b.page then
      -- every body line created before the request must ship before the band
      for _, pg in ipairs(S.pages) do
        for i = 1, pg.nentries do
          local e = pg.entries[i]
          local k = e.kind or KIND_BODY
          if S.mustship[e.seq] and k == KIND_BODY and e.seq <= b.req then
            local late = (pg.num > b.page)
              or (pg.num == b.page and e.idx > b.at)
            if late then
              bad = bad + 1
              if not first then
                first = { id = id, why = "seq=" .. e.seq .. " at=p" .. pg.num
                  .. "i" .. e.idx .. " band=p" .. b.page .. "i" .. b.at }
              end
            end
          end
        end
      end
    end
  end
  if bad == 0 then
    ok("band-order", "bands=" .. nbands)
  else
    fail("band-order", "bands=" .. nbands .. " bad=" .. bad
      .. " band=" .. first.id .. " " .. first.why)
  end
  return nbands
end

local function check_band_width(nbands)
  if nbands == 0 then
    ok("geometry-band-width", "bands=0")
    return
  end
  local g = S.pageinfo
  local limit = (g and g.width or 0) + TOL
  local bad, first = 0, nil
  for id, b in pairs(S.bands) do
    if b.x0 and b.x1 then
      local w = b.x1 - b.x0
      if w > limit then
        bad = bad + 1
        if not first then first = { id = id, w = w } end
      end
    end
  end
  if bad == 0 then
    ok("geometry-band-width", "bands=" .. nbands .. " max=" .. pt(limit - TOL))
  else
    fail("geometry-band-width", "band=" .. first.id .. " w=" .. pt(first.w)
      .. " max=" .. pt(limit - TOL))
  end
end

----------------------------------------------------------------------
-- sidecar
----------------------------------------------------------------------

local function jesc(s)
  return (tostring(s):gsub('[\\"]', '\\%0'))
end

local function write_sidecar(lines, nbands)
  local f = io.open(tex.jobname .. ".wbaudit.json", "w")
  if not f then return end
  f:write('{"version": 1,\n')
  f:write(' "summary": {"pages": ', S.page, ', "lines": ', lines,
          ', "bands": ', nbands, ', "footnotes": ', S.nfoot,
          ', "fails": ', S.fails, '},\n')
  f:write(' "patches": {')
  local sep = ""
  for name, applied in pairs(S.patches) do
    f:write(sep, '"', jesc(name), '": ', applied and "true" or "false")
    sep = ", "
  end
  f:write('},\n "fails": [')
  sep = ""
  for _, l in ipairs(S.faillines) do
    f:write(sep, '"', jesc(l), '"'); sep = ", "
  end
  f:write('],\n "pages": [\n')
  for i, pg in ipairs(S.pages) do
    if i > 1 then f:write(',\n') end
    f:write('  {"page": ', pg.num, ', "counter": ', pg.counter or 0,
            ', "body": ', pg.body or 0, ', "ink": ', pg.ink)
    if pg.rect then
      f:write(', "textarea": [', string.format("%.4f", pg.rect.left / SP), ', ',
              string.format("%.4f", pg.rect.top / SP), ', ',
              string.format("%.4f", pg.rect.right / SP), ', ',
              string.format("%.4f", pg.rect.bottom / SP), ']')
    end
    f:write(', "seq": [')
    for j = 1, pg.nentries do
      local e = pg.entries[j]
      if j > 1 then f:write(', ') end
      f:write('[', e.seq, ', ', e.kind or 0, ', ',
              string.format("%.2f", e.x / SP), ', ',
              string.format("%.2f", e.y / SP), ']')
    end
    f:write(']}')
  end
  f:write('\n ]}\n')
  f:close()
end

----------------------------------------------------------------------
-- wrapup
----------------------------------------------------------------------

-- The document level checks and the summary.  This runs from the
-- enddocument/end hook and not from wrapup_run, because LuaTeX 1.22 closes
-- the transcript before wrapup_run and texio.write_nl("log", ...) is then
-- lost; see docs/AUDIT.md.  It may run a second time from wrapup_run if a
-- page was shipped after \end{document}, so it is written to be repeatable.
function M.finish()
  local okc, err = pcall(M.run_document_checks)
  if not okc then
    logline("WBAUDIT ERROR " .. tostring(err))
    texio.write_nl("term and log", "WBAUDIT ERROR " .. tostring(err))
  end
end

function M.run_document_checks()
  if S.docbase == nil then
    S.docbase, S.docbaselines = S.fails, #S.faillines
  else
    S.fails = S.docbase
    for i = #S.faillines, S.docbaselines + 1, -1 do S.faillines[i] = nil end
  end
  for name, applied in pairs(S.patches) do
    if not applied then
      logline("WBAUDIT: patch-" .. name .. " skipped not-applied")
    end
  end
  S.nfoot = 0
  for _, rec in pairs(S.fn) do
    if rec.firsttext then S.nfoot = S.nfoot + 1 end
  end
  local lines = check_ledger_unique()
  local nbands = check_band_order()
  check_band_width(nbands)
  local summary = "WBAUDIT SUMMARY: pages=" .. S.page .. " lines=" .. lines
    .. " bands=" .. nbands .. " footnotes=" .. S.nfoot
    .. " fails=" .. S.fails
  texio.write_nl("log", summary)
  texio.write_nl("log", "")
  texio.write_nl("term", summary)
  S.finished = true
  if S.opts.json then
    local okw, err = pcall(write_sidecar, lines, nbands)
    if not okw then info("sidecar failed: " .. tostring(err)) end
  end
end

-- Safety net on the contract's wrapup_run callback: it runs the checks when
-- \end{document} never reached the hook, and it refreshes the sidecar when a
-- page was shipped after the summary was written.
function M.wrapup()
  if (not S.finished) or S.latepage then M.finish() end
end

return M
