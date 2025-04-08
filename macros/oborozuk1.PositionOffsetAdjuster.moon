export script_name = "Position Offset Adjuster"
export script_description = "Adjust subtitle position offset"
export script_author = "oborozuk1"
export script_version = "0.1.1"


ALLOWED_OFFSET = 6


haveDepCtrl, DependencyControl = pcall require, "l0.DependencyControl"
local depctrl, re, Ass, Line, Math
if haveDepCtrl
    depctrl = DependencyControl {
		feed: "https://raw.githubusercontent.com/TypesettingTools/ILL-Aegisub-Scripts/main/DependencyControl.json"
        {
            "aegisub.re"
            "ILL.ILL"
        }
    }
    re, ILL = depctrl\requireModules!
    {:Ass, :Line, :Math} = ILL
else
    re = require "aegisub.re"
    {:Ass, :Line, :Math} = require "ILL.ILL"


calc_offset = (line) ->
    path = Line.toPath line
    {l:left, r:right, :width} = path\boundingBox path
    leftOffset = left
    rightOffset = line.width - right
    offset = leftOffset - rightOffset
    if (math.abs offset) < ALLOWED_OFFSET
        return nil
    return Math.round offset, 0


apply_offset = (line, offset) ->
    if line.tags\existsTag "pos"
        {x, y} = line.tags\getTag("pos")\getValue!
        line.tags\insert { {"pos", "#{x - offset / 2},#{y}"} }
    else
        if offset > 0
            line.margin_r = line.eff_margin_r + offset
        else
            line.margin_l = line.eff_margin_l - offset


adjust_dialogue_offset = (sub, sel) ->
    in_dialogue = false
    ass = Ass sub, {}, 0
    for line, index, total in ass\iterSub!
        ass\progressLine index, index, total
        continue if line.class != "dialogue"
        
        Line.extend ass, line
        if line.comment and re.match line.text\get!, "^-{6,}\\s+Dialogue.*\\s+-{6,}"
            in_dialogue = true
        elseif line.comment and re.match line.text\get!, "^-{6,}\\s+.*\\s+-{6,}"
            in_dialogue = false
        continue if not in_dialogue or line.comment or line.tags\existsTag "pos"
        
        offset = calc_offset line
        if offset
            apply_offset line, offset
            ass\setLine line, index


adjust_selection_offset_with_pos = (sub, sel, active_line) ->
    ass = Ass sub, sel, active_line
    for line, sel_index, index, total in ass\iterSel!
        Line.extend ass, line
        ass\progressLine sel_index, index, total
        offset = calc_offset line
        if offset
            apply_offset line, offset
            ass\setLine line, sel_index


adjust_selection_offset = (sub, sel, active_line) ->
    ass = Ass sub, sel, active_line
    for line, sel_index, index, total in ass\iterSel!
        Line.extend ass, line
        ass\progressLine sel_index, index, total
        offset = calc_offset line
        if offset
            apply_offset line, offset
            ass\setLine line, sel_index


if haveDepCtrl
    depctrl\registerMacros {
        {"Adjust Dialogues", "Adjust Dialogue paragraphs' position, skipping lines with \\pos tag", adjust_dialogue_offset}
        {"Adjust Selection", "Adjust selected subtitles' position", adjust_selection_offset}
        {"Adjust Selection with \\pos", "Adjust selection using \\pos tag", adjust_selection_offset_with_pos}
    }
else
    aegisub.register_macro "#{script_name}/Adjust Dialogues", "Adjust Dialogue paragraphs' position, skipping lines with \\pos tag", adjust_dialogue_offset
    aegisub.register_macro "#{script_name}/Adjust Selection", "Adjust selected subtitles' position", adjust_selection_offset
    aegisub.register_macro "#{script_name}/Adjust Selection with \\pos", "Adjust selection using \\pos tag", adjust_selection_offset_with_pos

aegisub.register_filter "#{script_name}/Adjust Dialogues", "Adjust Dialogue paragraphs' position, skipping lines with \\pos tag", 6000, adjust_dialogue_offset
