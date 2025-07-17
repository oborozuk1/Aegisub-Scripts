export script_name = "Margin Adjuster"
export script_description = "Adjust subtitle position margins"
export script_author = "oborozuk1"
export script_version = "0.2.2"

ALLOWED_OFFSET = 6

haveDepCtrl, DependencyControl = pcall require, "l0.DependencyControl"
local depctrl, re, Ass, Config, Line, Math
if haveDepCtrl
  depctrl = DependencyControl {
		feed: "https://raw.githubusercontent.com/TypesettingTools/ILL-Aegisub-Scripts/main/DependencyControl.json"
    { "ILL.ILL" }
  }
  ILL = depctrl\requireModules!
  {:Ass, :Config, :Line, :Math} = ILL
else
  {:Ass, :Config, :Line, :Math} = require "ILL.ILL"

escape_pattern = (s) -> (s\gsub("(%W)", "%%%1"))

paragraph_pattern = (name) ->
  p = name == nil and ".-" or escape_pattern name
  return "^%-%-%-%-%-%-+%s+(#{p})%s+%-%-%-%-%-%-"

contains = (tbl, val) ->
  for v in *tbl
    return true if v == val
  return false

trim = (s) -> s\match "^%s*(.-)%s*$"

split = (str, sep = ",") ->
  pattern = string.format "([^%s]+)", sep
  return [ trim part for part in str\gmatch pattern ]

calcOffset = (line) ->
  path = Line.toPath line
  {l:left, r:right, :width} = path\boundingBox!
  leftOffset = left
  rightOffset = line.width - right
  return leftOffset, rightOffset

applyOffset = (ass, line, index, usingPos) ->
  offsetUsingPos = (line, offset, x, y) ->
    line.tags\insert { { "pos", { x + offset, y } } }
  
  return if line.tags\existsTag "move"
  leftOffset, rightOffset = calcOffset line
  offset = switch line.data.an
    when 1, 4, 7
      -leftOffset
    when 2, 5, 8
      -(leftOffset - rightOffset) / 2
    when 3, 6, 9
      rightOffset
  offset = Math.round offset, 2
  return unless ALLOWED_OFFSET < math.abs offset
  if line.tags\existsTag "pos"
    {x, y} = line.tags\getTag("pos")\getValue!
    offsetUsingPos line, offset, x, y
  else if usingPos
    {:x, :y} = line
    offsetUsingPos line, offset, x, y
  else
    switch line.data.an
      when 1, 4, 7
        m = Math.round line.eff_margin_l + offset, 0
        if m > 0
          line.margin_l = m
        else
          {:x, :y} = line
          offsetUsingPos line, offset, x, y
      when 2, 5, 8
        if offset > 0
          line.margin_l = line.eff_margin_l + offset
        else
          line.margin_r = line.eff_margin_r - offset
      when 3, 6, 9
        m = Math.round line.eff_margin_r - offset, 0
        if m > 0
          line.margin_r = m
        else
          {:x, :y} = line
          offsetUsingPos line, offset, x, y
  Ass.setText line
  ass\setLine line, index

adjustParagraphs = (sub, names) ->
  ass = Ass sub, {}, 0
  namesMap = { name, true for name in *names }
  currParagraph = nil
  pattern = paragraph_pattern!
  for line, i, t in ass\iterSub!
    -- ass\progressLine i, i, t
    continue unless line.class == "dialogue"
    if line.comment
      match = line.text\match pattern
      currParagraph = match if match
      continue
    continue if not namesMap[currParagraph]
    Line.extend ass, line
    continue if line.tags\existsTagOr "pos", "move"
    applyOffset ass, line, i

adjustDialogue = (sub) ->
  adjustParagraphs sub, { "Dialogue CN", "Dialogue JP", "Dialogue" }

adjustParagraphsDialog = (sub) ->
  button, result = aegisub.dialog.display {
    { class: "textbox", name: "names", width: 50, height: 5 }
  }
  if button
    adjustParagraphs sub, split result.names

adjustSelection = (usingPos) ->
  (sub, sel) ->
    ass = Ass sub, sel, 0
    for line, s, i, t in ass\iterSel!
      Line.extend ass, line
      -- ass\progressLine s, i, t
      applyOffset ass, line, s, usingPos

if haveDepCtrl
  depctrl\registerMacros {
    { "Adjust Dialogues", "Adjust Dialogue paragraphs' margin, skipping lines with \\pos tag", adjustDialogue }
    { "Adjust Paragraphs", "Adjust paragraphs' margin, skipping lines with \\pos tag", adjustParagraphsDialog }
    { "Adjust Selection", "Adjust selected subtitles' margin", adjustSelection! }
    { "Adjust Selection using \\pos", "Adjust selection using \\pos tag", adjustSelection true }
  }
else
  aegisub.register_macro "#{script_name}/Adjust Dialogues", "Adjust Dialogue paragraphs' margin, skipping lines with \\pos tag", adjustDialogue
  aegisub.register_macro "#{script_name}/Adjust Paragraphs", "Adjust paragraphs' margin, skipping lines with \\pos tag", adjustParagraphsDialog
  aegisub.register_macro "#{script_name}/Adjust Selection", "Adjust selected subtitles' margin", adjustSelection!
  aegisub.register_macro "#{script_name}/Adjust Selection using \\pos", "Adjust selection using \\pos tag", adjustSelection true

aegisub.register_filter "#{script_name}/Adjust Dialogues", "Adjust Dialogue paragraphs' margin, skipping lines with \\pos tag", 6000, adjustDialogue
