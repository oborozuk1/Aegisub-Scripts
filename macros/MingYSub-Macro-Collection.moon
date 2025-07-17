export script_name = "MingYSub Macro Collection"
export script_description = "适用于 MingYSub 的实用字幕处理工具"
export script_author = "Ming"
export script_version = "0.3.0"

math = require "math"
unicode = require "unicode"
re = require "re"

sgn = (x) -> if x > 0 then 1 else if x < 0 then -1 else 0

clamp = (val, min, max) -> math.min max, math.max val, min

iterRange = (start, stop, step = 1) ->
  if stop == nil
    stop = start
    start = 1
  if stop == start
    returned = false
    return () -> if returned = not returned return start
  if step == 0 or sgn(step) != sgn(stop - start) return () -> nil
  i = start - step
  return () ->
    i += step
    if (step > 0 and i <= stop) or (step < 0 and i >= stop) then
      return i

range = (start, stop, step) -> [ i for i in iterRange start, stop, step ]

trim = (s) -> s\match "^%s*(.-)%s*$"

count = (s, pattern) -> select 2, s\gsub pattern, ""

escapePattern = (s) -> (s\gsub "(%W)", "%%%1")

insert = (t, value, pos) ->
  if pos
    table.insert t, pos, value
  else
    table.insert t, value

extend = (tbl, values) ->
  for v in *values
    insert tbl, v
  return tbl

map = (t, fn) ->
  for i in *t do t[i] = fn t[i]
  return t

copy = (t, deep, seen = {}) ->
  return if t == nil
  return seen[t] if seen[t]
  nt = {}
  for k, v in pairs t
    nt[k] = if deep and type(v) == "table" then table.copy(v, deep, seen) else v
  setmetatable nt, table.copy getmetatable(t), deep, seen
  seen[t] = nt
  return nt

split = (s, pattern, splitStart, plain) ->
  ret = {}
  splitStart, length = 1, #s
  while splitStart <= length
    sepStart, sepEnd = s\find pattern, splitStart, plain
    unless sepStart
      insert ret, s\sub splitStart
      break
    if sepStart > splitStart
      insert ret, s\sub splitStart, sepStart - 1
    else
      insert ret, ""
    splitStart = sepEnd + 1
  return ret

splitTextByRatio = (str, delimiter, ratio = 0.5) ->
  return str, str if ratio <= 0 or ratio >= 1
  splits = split str, delimiter
  return str, str if #splits <= 1
  positions = {}
  sum = 0
  for s in *splits
    sum += #s
    insert positions, sum
    sum += #delimiter
  targetPos = math.floor #str * ratio
  closest = positions[1]
  minDiff = math.abs closest - targetPos
  for pos in *positions
    diff = math.abs pos - targetPos
    if diff < minDiff
      closest = pos
      minDiff = diff
  return str\sub(1, closest), str\sub(closest + #delimiter + 1)

inTable = (value, tbl) ->
  for v in *tbl
    return true if v == value
  return false

addTable = (...) ->
  ret = {}
  for tbl in *{...}
    insert ret, item for item in *tbl
  return ret

stripTags = (s) -> (s\gsub "{[^}]+}", "")

log = (message, end_) ->
  aegisub.log message == nil and "<nil>" or tostring message
  aegisub.log end_ and tostring(end_) or "\n"

error = (message) ->
  aegisub.log message if message
  aegisub.cancel!

userConfig = nil

loadConfig = () ->
  return if userConfig
  config = {
    presets: {
      original: {
        JP: {
          keyword: "JP"
          connector: "　"
          -- maxLength: 35
          -- maxCps: 8
        }
        EN: {
          keyword: "EN"
          connector: " "
          -- maxLength: 40
          -- maxCps: 20
        }
      }
      translation: {
        CN: {
          keyword: "CN"
          connector: " "
          -- maxLength: 23
          -- maxCps: 8
        }
      }
      paragraphPattern: {
        "%-%-%-%-%-%-%s+#%s+%-%-%-%-%-%-"
        "%-%-%-%-%-%-%s*#%s*%-%-%-%-%-%-"
      }
      dialogue: { "Dialogue ~" }
      paragraphs: { "Dialogue ~", "OP~", "ED~", "IN~", "Sign", "Title", "Note", "Comment", "Credits", "Staff" }
      split: {
        partition: { "。", "\\N" }

      }
    }
    current: {
      original: { "JP", "EN" }
      translation: { "CN" }
      paragraphPattern: "%-%-%-%-%-%-%-*%s*#%s*%-%-%-%-%-%-"
      insertPattern: "------ # ------"
      dialogue: "Dialogue ~"
      paragraphs: { "Dialogue ~", "OP~", "ED~", "IN~", "Sign", "Title", "Note", "Comment", "Credits", "Staff" }
      split: {
        partition: { "。", "\\N" }
        translationLayer: 7
        originalLayer: 5
      }
    }
  }
  userConfig = {}
  with userConfig
    .original = [ config.presets.original[lang] for lang in *config.current.original ]
    .translation = [ config.presets.translation[lang] for lang in *config.current.translation ]
    .paragraphPattern = config.current.paragraphPattern
    .insertPattern = config.current.insertPattern
    .dialogue = config.current.dialogue
    .paragraphs = config.current.paragraphs
    .split = config.current.split
    .languages = addTable [ lang.keyword for lang in *.original ], [ lang.keyword for lang in *.translation ]

paragraphPattern = (name) ->
  if name == nil or #name == 0
    return userConfig.paragraphPattern\gsub "#", "(.-)"
  return userConfig.paragraphPattern\gsub "#", escapePattern name

isOriginal = (name) ->
  name = trim name
  for lang in *userConfig.original
    return true, lang.keyword if name\find lang.keyword
  return false

isTranslation = (name) ->
  name = trim name
  for lang in *userConfig.translation
    return true, lang.keyword if name\find lang.keyword
  return false

detectLanguage = (name) ->
  name = trim name
  for lang in *userConfig.original
    return lang if name\find lang.keyword
  for lang in *userConfig.translation
    return lang if name\find lang.keyword

isDialogue = (name) ->
  name = trim name
  for lang in *userConfig.languages
    return true if name == userConfig.dialogue\gsub "~", lang.keyword
  return false

convertType = (name) ->
  name = trim name
  original, lang = isOriginal name
  if original
    return [ name\gsub lang, t.keyword for t in *userConfig.translation ], lang, [ t.keyword for t in *userConfig.translation ]
  translation, lang = isTranslation name
  if translation
    return [ name\gsub lang, t.keyword for t in *userConfig.original ], lang, [ t.keyword for t in *userConfig.original ]

getStyles = (sub) ->
  styles = {}
  for l in *sub
    if l.class == "style"
      insert styles, l
    else if l.class != "info"
      break
  return styles

createLine = (tbl) ->
  {
    comment: tbl.comment or false
    layer: tbl.layer or 0
    start_time: tbl.start_time or 0
    end_time: tbl.end_time or 0
    style: tbl.style or "Default"
    effect: tbl.effect or ""
    actor: tbl.actor or ""
    text: tbl.text or ""
    margin_l: tbl.margin_l or 0
    margin_r: tbl.margin_r or 0
    margin_b: tbl.margin_b or 0
    margin_t: tbl.margin_t or 0
    class: "dialogue"
    section: "[Events]"
  }

getIndexOffset = (sub) ->
  for i, line in ipairs sub
    return i - 1 if line.class == "dialogue"
  return 0

getAllParagraphs = (sub) ->
  paragraphs = {}
  nullParagraph = { name: "~NULL", start_i: getIndexOffset(sub) + 1, end_i: 0 }
  for i, line in ipairs sub
    continue unless line.comment
    match = line.text\match paragraphPattern!
    continue unless match
    if nullParagraph.end_i == 0
      nullParagraph.end_i = i - 1
    if #paragraphs != 0
      paragraphs[#paragraphs].end_i = i - 1
    insert paragraphs, { name: match, start_i: i, end_i: nil }
  if nullParagraph.end_i == 0
    nullParagraph.end_i = #sub
  if nullParagraph.end_i >= nullParagraph.start_i
    insert paragraphs, nullParagraph, 1
  paragraphs[#paragraphs].end_i = if sub[#sub].comment and
    sub[#sub].text == "" then #sub - 1 else #sub
  for i, para in ipairs paragraphs
    para.index = i
  return paragraphs

getParagraphsMap = (sub, paragraphs = getAllParagraphs sub) ->
  { para.name, para for para in *paragraphs }

getParagraphBySel = (sub, sel, paragraphs = getAllParagraphs sub) ->
  return {} if #sel == 0 or #paragraphs == 0
  ret = {}
  j = 1
  for i = 1, #paragraphs
    flag = false
    while j <= #sel and sel[j] <= paragraphs[i].end_i
      flag = true
      j += 1
    insert ret, paragraphs[i] if flag
    break if j > #sel
  return ret, paragraphs

getCorrespondingParagraph = (paragraphsMap, paragraphName) ->
  targetNames = convertType paragraphName
  return unless targetNames
  for targetName in *targetNames
    targetParagraph = paragraphsMap[targetName]
    return targetParagraph if targetParagraph

checkCorrespondingParagraphLength = (sub, paragraph, paragraphsMap = getParagraphsMap sub) ->
  name = paragraph.name
  targetParagraph = getCorrespondingParagraph paragraphsMap, name
  error "未找到对应段落: #{name}" unless targetParagraph
  return targetParagraph.end_i - targetParagraph.start_i ==
    paragraph.end_i - paragraph.start_i, targetParagraph

checkParagraphMode = (sub, sel, paragraphsMap, selParagraphs) ->
  unless paragraphsMap and selParagraphs
    allParagraphs = getAllParagraphs sub
    unless paragraphsMap
      paragraphsMap = getParagraphsMap sub, allParagraphs
    unless selParagraphs
      selParagraphs = getParagraphBySel sub, sel, allParagraphs
  targetParagraphMapping = {}
  for p in *selParagraphs
    if p.name != selParagraphs[1].name
      return false
    targetParagraph = getCorrespondingParagraph paragraphsMap, p.name
    unless targetParagraph
      return false
    unless checkCorrespondingParagraphLength sub, p, paragraphsMap
      error "段落长度不一致，请检查"
    targetParagraphMapping[p.name] = targetParagraph
  targetIndices = {}
  i = 1
  for p in *selParagraphs
    targetParagraph = targetParagraphMapping[p.name]
    offset = targetParagraph.start_i - p.start_i
    while i <= #sel and sel[i] <= p.end_i
      targetIndices[i] = sel[i] + offset
      i += 1
  return true, targetParagraphMapping, targetIndices

getPrevParagraphMarkIndex = (sub, idx) ->
  for i = idx - 1, 1, -1
    line = sub[i]
    return if line.class != "dialogue"
    if line.comment and line.text\match paragraphPattern!
      return i

getNextParagraphMarkIndex = (sub, idx) ->
  for i = idx + 1, #sub
    line = sub[i]
    if line.comment and line.text\match paragraphPattern!
      return i

insertParagraphMark = (sub, i, name, comment = "", style = "Default", time = 0) ->
  text = userConfig.insertPattern\gsub "#", name
  text = text .. " " .. comment if #comment > 0
  line = createLine { comment: true, text: text, style: style, start_time: time, end_time: time }
  sub.insert i, line if i >= 0
  return line

applyToCorrespondingParagraph = (sub, sel) ->
  selParagraphs, allParagraphs = getParagraphBySel sub, sel
  selParagraphsMap = { p.name, p for p in *selParagraphs }
  for p in *selParagraphs
    names = convertType p.name
    continue unless names
    for name in *names
      if selParagraphsMap[name]
        error "不能同时选中两种语言的段落"
  paragraphsMap = getParagraphsMap sub, allParagraphs
  targetParagraphs = {}
  for p in *selParagraphs
    flag, targetParagraph = checkCorrespondingParagraphLength sub, p, paragraphsMap
    if flag
      targetParagraphs[p.name] = targetParagraph
    else
      error "段落长度不一致，请检查"
  for p in *selParagraphs
    targetParagraph = targetParagraphs[p.name]
    lang = detectLanguage p.name
    targetLang = detectLanguage targetParagraph.name
    start = p.start_i
    targetStart = targetParagraph.start_i
    for i in iterRange 0, p.end_i - p.start_i
      line = sub[start + i]
      targetLine = sub[targetStart + i]
      targetLine.comment = line.comment
      targetLine.style = line.style\gsub lang.keyword, targetLang.keyword
      targetLine.start_time = line.start_time
      targetLine.end_time = line.end_time
      targetLine.margin_l = line.margin_l
      targetLine.margin_r = line.margin_r
      targetLine.effect = line.effect
      if line.actor\sub(1, 1) != "*" and targetLine.actor\sub(1, 1) != "*"
        targetLine.actor = line.actor
      sub[targetStart + i] = targetLine

duplicateSelection = (sub, sel) ->
  doDuplicate = (sub, sel) ->
    ranges = {}
    lines = { sub[sel[#sel]] }
    pos = sel[#sel] + 1
    for i = #sel - 1, 1, -1
      if sel[i] + 1 != sel[i + 1]
        sub.insert pos, unpack lines
        insert ranges, { pos, pos + #lines - 1 }, 1
        lines = {}
        pos = sel[i] + 1
      insert lines, sub[sel[i]], 1
    if #lines > 0
      insert ranges, { pos, pos + #lines - 1 }, 1
      sub.insert pos, unpack lines
    ret = {}
    count = 0
    for i in *ranges
      { start, stop } = i
      extend ret, range start + count, stop + count
      count += stop - start + 1
    return ret

  selParagraphs, allParagraphs = getParagraphBySel sub, sel
  paragraphsMap = getParagraphsMap sub, allParagraphs
  paragraphMode, targetParagraphMapping, targetIndices = checkParagraphMode sub, sel, paragraphsMap, selParagraphs
  return doDuplicate sub, sel unless paragraphMode
  ret = nil
  if sel[1] < targetIndices[1]
    doDuplicate sub, targetIndices
    ret = doDuplicate sub, sel
  else
    ret = doDuplicate sub, sel
    count = doDuplicate sub, targetIndices
    map ret, (i) -> i + #count
  return ret

joinLines = (sub, sel) ->
  smartJoin = (sub, sel) ->
    lang = detectLanguage sub[sel[1]].style
    connector = lang and lang.connector or " "
    newLine = sub[sel[1]]
    newLine.text = ""
    startTime = sub[sel[1]].start_time
    endTime = sub[sel[1]].end_time
    texts = {}
    last = nil
    for i in *sel
      line = sub[i]
      textStripped = stripTags line.text
      startTime = math.min startTime, line.start_time
      endTime = math.max endTime, line.end_time
      continue if textStripped\gsub(" ", "")\gsub("　", "") == ""
      continue if textStripped == last
      -- TODO: handle tags
      insert texts, line.text
      last = textStripped
    newLine.text = table.concat texts, connector
    newLine.start_time = startTime
    newLine.end_time = endTime
    return newLine

  selParagraphs, allParagraphs = getParagraphBySel sub, sel
  paragraphsMap = getParagraphsMap sub, allParagraphs
  paragraphMode, targetParagraphMapping, targetIndices = checkParagraphMode sub, sel, paragraphsMap, selParagraphs
  line = smartJoin sub, sel
  unless paragraphMode
    sub.delete sel
    sub.insert sel[1], line
    return { sel[1] }
  targetLine = smartJoin sub, targetIndices
  if sel[1] < targetIndices[1]
    sub.delete targetIndices
    sub.insert targetIndices[1], targetLine
    sub.delete sel
    sub.insert sel[1], line
    return { sel[1] }
  else
    sub.delete sel
    sub.insert sel[1], line
    sub.delete targetIndices
    sub.insert targetIndices[1], targetLine
    return { sel[1] - #sel + 1 }

jumpToNextParagraphMark = (sub, sel) ->
  i = getNextParagraphMarkIndex sub, sel[#sel]
  return if i then { i } else { #sub }

jumpToPrevParagraphMark = (sub, sel) ->
  i = getPrevParagraphMarkIndex sub, sel[1]
  return if i then { i } else { 1 + getIndexOffset sub }

jumpToCorrespondingLine = (sub, sel) ->
  selParagraphs, allParagraphs = getParagraphBySel sub, sel
  paragraphsMap = getParagraphsMap sub, allParagraphs
  res = {}
  i = 1
  for p in *selParagraphs
    targetParagraph = getCorrespondingParagraph paragraphsMap, p.name
    error "未找到对应段落: #{p.name}" unless targetParagraph
    offset = targetParagraph.start_i - p.start_i
    while i <= #sel and sel[i] <= p.end_i
      insert res, clamp sel[i] + offset, targetParagraph.start_i,  targetParagraph.end_i
      i += 1
  return res

moveParagraphsDown = (sub, sel) ->
  selParagraphs, allParagraphs = getParagraphBySel sub, sel
  lengths = [ p.end_i - p.start_i + 1 for p in *allParagraphs ]
  ret = {}
  for j = #selParagraphs, 1, -1
    p = selParagraphs[j]
    if p.index == #allParagraphs
      extend ret, range p.start_i, p.end_i
      continue
    offset = lengths[p.index + 1]
    for i in iterRange 0, p.end_i - p.start_i
      sub.insert p.end_i + offset + i + 1, sub[p.start_i + i]
      insert ret, p.start_i + offset + i
    sub.deleterange p.start_i , p.end_i
    lengths[p.index] = lengths[p.index + 1]
  return ret

moveParagraphsUp = (sub, sel) ->
  selParagraphs, allParagraphs = getParagraphBySel sub, sel
  lengths = [ p.end_i - p.start_i + 1 for p in *allParagraphs ]
  ret = {}
  for p in *selParagraphs
    if p.index == 1
      extend ret, range p.start_i, p.end_i
      continue
    offset = lengths[p.index - 1]
    for i in iterRange 0, p.end_i - p.start_i
      sub.insert p.start_i - offset + i, sub[p.start_i + i * 2]
      insert ret, p.start_i - offset + i
    sub.deleterange p.start_i + lengths[p.index], p.end_i + lengths[p.index]
    lengths[p.index] = lengths[p.index - 1]
  return ret

selectParagraphs = (sub, sel) ->
  s = getPrevParagraphMarkIndex(sub, sel[1]) or 1 + getIndexOffset sub
  e = getNextParagraphMarkIndex(sub, sel[#sel]) or #sub + 1
  return range s, e - 1

splitActiveLineAtCurrentFrame = (sub, _, act) ->
  doSplit = (sub, i) ->
    line = sub[i]
    lineCopy = sub[i]
    if line.end_time <= line.start_time
      sub.insert i + 1, lineCopy
      return { i + 1 }
    videoTime = aegisub.ms_from_frame aegisub.project_properties!.video_position
    ratio = (videoTime - line.start_time) / (line.end_time - line.start_time)
    if ratio <= 0 or ratio >= 1
      sub.insert i + 1, lineCopy
      return { i + 1 }
    lang = detectLanguage(line.style)
    line.text, lineCopy.text = splitTextByRatio line.text, lang.connector or " ", ratio
    line.end_time = videoTime
    lineCopy.start_time = videoTime
    sub[i] = line
    sub.insert i + 1, lineCopy
    return { i + 1 }

  selParagraphs, allParagraphs = getParagraphBySel sub, { act }
  paragraphsMap = getParagraphsMap sub, allParagraphs
  paragraphMode, targetParagraphMapping, targetIndices = checkParagraphMode sub, { act }, paragraphsMap, selParagraphs
  ret = doSplit sub, act
  return ret unless paragraphMode
  if act > targetIndices[1]
    ret[1] += 1
  else
    targetIndices[1] += 1
  doSplit sub, targetIndices[1]
  return ret

splitBilingualParagraphs = (sub, sel) ->
  selParagraphs = getParagraphBySel sub, sel
  indexOffset = getIndexOffset sub
  for i = #selParagraphs, 1, -1
    paragraph = selParagraphs[i]
    targetParagraphNames = convertType paragraph.name
    error "段落名称不含语言代码: #{paragraph.name}" unless targetParagraphNames
    failFlag = false
    partitions = userConfig.split.partition
    languageMapping = {}
    for i = paragraph.start_i, paragraph.end_i
      l = sub[i]
      if i != paragraph.start_i
        last = partitions
        partitions = [ p for p in *partitions when l.text\find p, 1, true ]
        if #partitions == 0
          log ("第 %d 行不包含分隔符: %s")\format i - indexOffset, table.concat last, "|"
          partitions = last
          failFlag = true
      continue if languageMapping[l.style]
      targetNames, lang, targetLanguages = convertType l.style
      if lang
        languageMapping[l.style] = {
          targetName: targetNames[1]
          targetLanguage: targetLanguages[1]
          lang: lang
        }
      else
        log ("第 %d 行样式未能找到语言代码: %s")\format i, table.concat userConfig.languages, "|"
        failFlag = true
    aegisub.cancel! if failFlag
    targetParagraphName = targetParagraphNames[1]
    partition = partitions[1]
    layer1, layer2 = userConfig.split.translationLayer, userConfig.split.originalLayer
    if isOriginal paragraph.name
      layer1, layer2 = layer2, layer1
    l = sub[paragraph.start_i]
    l.layer = layer1
    sub[paragraph.start_i] = l
    l.text = insertParagraphMark(sub, -1, targetParagraphName).text
    l.style = languageMapping[l.style].targetName
    l.layer = layer2
    sub.insert paragraph.end_i + 1, l
    for i = paragraph.start_i + 1, paragraph.end_i
      l = sub[i]
      text = l.text
      tag = text\match("^{.-}") or ""
      l.text = text\match "(.-)#{partition}"
      l.layer = layer1
      sub[i] = l
      l.text = tag .. text\match ".-#{partition}(.*)"
      l.style = languageMapping[l.style].targetName
      l.layer = layer2
      sub.insert paragraph.end_i + i - paragraph.start_i + 1, l

insertParagraphMarkInterface = (sub, sel) ->
  lang = detectLanguage sub[sel[1]].style
  btn, res = aegisub.dialog.display {
    { class: "label", label: "Paragraph mark:", x: 0, y: 0 }
    { class: "edit", name: "mark", x: 1, y: 0, width: 8 }
    { class: "label", label: "Select from:", x: 0, y: 1 }
    { class: "dropdown", name: "para", x: 1, y: 1, items: userConfig.paragraphs }
    { class: "dropdown", name: "lang", x: 2, y: 1, items: addTable({ "NULL" }, userConfig.languages), value: lang.keyword }
    { class: "label", label: "Comment:", x: 0, y: 2 }
    { class: "edit", name: "comment", x: 1, y: 2, width: 8 }
    { class: "label", label: "Style:", x: 0, y: 3 }
    { class: "dropdown", name: "style", x: 1, y: 3, items: [ s.name for s in *getStyles(sub) ], value: sub[sel[1]].style }
    { class: "checkbox", name: "time", label: "Use frame time", x: 0, y: 4 }
    { class: "checkbox", name: "after", label: "Insert after line", x: 1, y: 4 }
  }
  return unless btn
  mark = res.mark
  if #mark == 0
    if res.lang and res.lang != "NULL"
      mark = res.para\gsub "~", res.lang
    else
      mark = res.para\gsub "%s?~", ""
  if #mark == 0
    error "No paragraph mark provided."
  index = if res.after then sel[1] + 1 else sel[1]
  time = 0
  if res.time
    time = aegisub.ms_from_frame aegisub.project_properties!.video_position
  insertParagraphMark sub, index, mark, res.comment, res.style, time
  return { index }

selectMoreThan = (n) -> (_, sel) -> #sel > n

inParagraph = (sub, sel) ->
  return false if #sel == 0
  return true unless userConfig
  return getPrevParagraphMarkIndex sub, sel[1]

register = (name, description, fn, check) ->
  call = (fn) ->
    (sub, sel, act) ->
      loadConfig!
      fn sub, sel, act
  aegisub.register_macro "#{script_name}/#{name}", description, call(fn), check

register "Apply to Corresponding Para", "Apply timing etc. to corresponding paragraph", applyToCorrespondingParagraph, selectMoreThan 0
register "Duplicate Selection", "Duplicate selected subtitles", duplicateSelection, selectMoreThan 0
register "Insert Para Mark", "Insert paragraph mark", insertParagraphMarkInterface, selectMoreThan 0
register "Join Lines (Smart)", "Smart join lines (bilingual)", joinLines, selectMoreThan 1
register "Jump to Corresponding Line", "Jump to corresponding line in bilingual paragraphs", jumpToCorrespondingLine, selectMoreThan 0
register "Jump to Next Para Mark", "Jump to next paragraph mark", jumpToNextParagraphMark, selectMoreThan 0
register "Jump to Prev Para Mark", "Jump to previous paragraph mark", jumpToPrevParagraphMark, selectMoreThan 0
register "Move Paras Down", "Move selected paragraphs down", moveParagraphsDown, selectMoreThan 0
register "Move Paras Up", "Move selected paragraphs up", moveParagraphsUp, selectMoreThan 0
register "Select Paras", "Select entire paragraph(s)", selectParagraphs, selectMoreThan 0
register "Split Active Line At Current Frame", "Split line (timing and text) at current frame", splitActiveLineAtCurrentFrame
register "Split Bilingual Paras", "Split bilingual paragraphs", splitBilingualParagraphs, inParagraph

