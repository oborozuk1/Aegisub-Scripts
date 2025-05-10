script_name = "MingYSub Scripts"
script_description = "适用于 MingYSub 的实用字幕处理工具"
script_author = "Ming"
script_version = "0.2.4"

local cn_str = "CN"
local jp_str = "JP"
local cn_paragraph_name = "Dialogue CN"
local jp_paragraph_name = "Dialogue JP"
local bi_partition = "。"
local cn_max_length = 23
local jp_max_length = 35

local math = require "math"
local unicode = require "unicode"
local re = require "re"

local unrecommended_patterns = {
    -- {
    --     patterns = { ".{.-}" },
    --     message = "行内有标签",
    --     only_dialogue = true,
    -- },
    {
        patterns = { "%.%." },
        message = "应使用中文标点",
        only_dialogue = true,
    },
    {
        patterns = {
            "以经", "在次", "即然", "既使", "亦或", "汇合", "装帧", "凑和", "渲泄",
            "寒喧", "真象", "松驰", "粗旷", "按装", "份内", "栽脏", "笑魇", "窝笋",
            "摄相",
            "(不止).*而且", "[的多少好](途经)",
            "挖墙角", "水蒸汽", "泊来品", "天燃气",
            "迫不急待", "再接再励", "一愁莫展", "谈笑风声", "饮鸠止渴", "自抱自弃",
            "淡薄名利",
        },
        message = "可能存在错字，请检查",
    },
    {
        patterns = { "桔子", "其它", "称做" },
        message = "应使用规范字",
    },
    {
        patterns = {
            "[让令使叫][人我][不难]?堪",
            "(无时无刻)[^不没]*"
        },
        message = "搭配不当",
    },
    {
        patterns = {
            "羁绊", "料理",
            "差强人意",
        },
        message = "不建议使用词汇",
    },
    {
        patterns = {
            "凯旋(?:而归|归来)",
        },
        message = "不建议使用词汇",
        full_regex = true,
    },

}

function table.copy(t, deep, seen)
    seen = seen or {}
    if t == nil then return nil end
    if seen[t] then return seen[t] end
    local nt = {}
    for k, v in pairs(t) do
        if deep and type(v) == 'table' then
            nt[k] = table.copy(v, deep, seen)
        else
            nt[k] = v
        end
    end
    setmetatable(nt, table.copy(getmetatable(t), deep, seen))
    seen[t] = nt
    return nt
end

local function escape_pattern(s)
    return (s:gsub("(%W)", "%%%1"))
end

local function split(text, pattern, plain)
    local ret = {}
    local splitStart, length = 1, #text
    while splitStart <= length do
        local sepStart, sepEnd = string.find(text, pattern, splitStart, plain)
        if not sepStart then
            table.insert(ret, string.sub(text, splitStart))
            break
        end
        if sepStart > splitStart then
            table.insert(ret, string.sub(text, splitStart, sepStart - 1))
        else
            table.insert(ret, "")
        end
        splitStart = sepEnd + 1
    end
    return ret
end

local function strip_tags(s)
    return (s:gsub("{[^}]+}", ""))
end

local function in_table(t, ele)
    for _, i in ipairs(t) do
        if i == ele then
            return true
        end
    end
    return false
end

-- 去除首尾空格
local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

local function count(s, pattern)
    return select(2, s:gsub(pattern, ""))
end

local function log(text, end_)
    aegisub.debug.out(text == nil and "<nil>" or tostring(text))
    aegisub.debug.out(end_ and tostring(end_) or "\n")
end

-- 返回段落正则表达式
local function paragraph_pattern(name)
    if name == nil or #name == 0 then
        return "^%-%-%-%-%-%-+%s+(.-)%s+%-%-%-%-%-%-"
    end
    return "^%-%-%-%-%-%-+%s+(" .. escape_pattern(name) .. ")%s+%-%-%-%-%-%-"
end

local function is_cn_line(line)
    return line.style:find(cn_str) ~= nil
end

local function is_jp_line(line)
    return line.style:find(jp_str) ~= nil
end

local function get_index_offset(sub)
    for i, line in ipairs(sub) do
        if line.class == "dialogue" then
            return i - 1
        end
    end
    return 0
end

-- 转换中日段落/样式名称
local function trans_style_name(name)
    if name:find(cn_str) then
        return (name:gsub(cn_str, jp_str))
    elseif name:find(jp_str) then
        return (name:gsub(jp_str, cn_str))
    end
    return nil
end

-- 获取所有段落
local function get_all_paragraphs(sub)
    local paragraphs = {}
    local null_paragraph = { name = "~NULL", start_i = get_index_offset(sub) + 1, end_i = 0 }
    for i, line in ipairs(sub) do
        if not line.comment then
            goto continue
        end
        local match = line.text:match(paragraph_pattern())
        if match then
            if null_paragraph.end_i == 0 then
                null_paragraph.end_i = i - 1
            end
            local cur_paragraph = match
            if #paragraphs ~= 0 then
                paragraphs[#paragraphs].end_i = i - 1
            end
            paragraphs[#paragraphs + 1] = {
                name = cur_paragraph,
                start_i = i,
                end_i = nil
            }
        end
        ::continue::
    end

    if null_paragraph.end_i ~= 0 then
        table.insert(paragraphs, 1, null_paragraph)
    end

    if #paragraphs == 0 then
        return {}
    end

    if sub[#sub].comment and sub[#sub].text == "" then
        paragraphs[#paragraphs].end_i = #sub - 1
    else
        paragraphs[#paragraphs].end_i = #sub
    end

    return paragraphs -- { { name , start_i , end_i }, ... }
end

-- 获取所有段落哈希表格式，重复段落名只保留最后一个
local function get_paragraphs_map(sub, paragraphs)
    paragraphs = paragraphs or get_all_paragraphs(sub)
    local res = {}
    for _, p in ipairs(paragraphs) do
        res[p.name] = p
    end
    return res
end

-- 获取选中的段落
local function get_paragraphs_by_sel(sub, sel, paragraphs)
    paragraphs = paragraphs or get_all_paragraphs(sub)
    if #paragraphs == 0 then
        return {}
    end

    local paragraphs_needed = {}
    local paragraphs_set = {}
    -- 倒序遍历选中的行，找到对应的段落
    local j = #paragraphs
    for i = #sel, 1, -1 do
        if sel[i] > paragraphs[j].end_i then
            goto continue
        end
        while j > 1 and sel[i] < paragraphs[j].start_i do
            j = j - 1
        end
        if sel[i] >= paragraphs[j].start_i and sel[i] <= paragraphs[j].end_i then
            if paragraphs_set[paragraphs[j].end_i] == nil then
                table.insert(paragraphs_needed, paragraphs[j])
                paragraphs_set[paragraphs[j].end_i] = true
            end
        end
        ::continue::
    end

    return paragraphs_needed
end

-- 获取中日行范围
local function get_dialogue_range(sub)
    local paragraphs_map = get_paragraphs_map(sub)
    local cn_para = paragraphs_map[cn_paragraph_name]
    local jp_para = paragraphs_map[jp_paragraph_name]
    if not cn_para or not jp_para then
        return nil, nil
    end
    local cn_range = { start_i = cn_para.start_i, end_i = cn_para.end_i }
    local jp_range = { start_i = jp_para.start_i, end_i = jp_para.end_i }
    return cn_range, jp_range
end

-- 检查对应段落长度
local function check_corresponding_paragraph_length(sub, paragraph, paragraphs_map)
    paragraphs_map = paragraphs_map or get_paragraphs_map(sub)
    local name = paragraph.name
    local target_name = trans_style_name(name)
    if not target_name then
        log(name .. " 未能找到语言代码(CN/JP)")
        return nil
    end
    if not paragraphs_map[target_name] then
        log("未找到对应的段落" .. target_name)
        return nil
    end
    local target_para = paragraphs_map[target_name]
    return paragraph.end_i - paragraph.start_i == target_para.end_i - target_para.start_i
end

local function split_line_text(line)
    local line2 = table.copy(line)
    local tag = line.text:match("^{.-}") or ""
    line.text = line.text:match("(.-)" .. bi_partition)
    line.layer = 6
    line2.text = tag .. line2.text:sub(#line.text + #bi_partition + 1)
    -- line2.text = tag .. line2.text:match(".-" .. bi_partition .. "(.*)")
    line2.style = trans_style_name(line2.style)
    line2.layer = 7
    return line, line2
end

-- 拆分选定段落的中日轴
local function split_bilingual_paragraphs(sub, sel)
    local paragraphs = get_paragraphs_by_sel(sub, sel)

    for i = #paragraphs, 1, -1 do
        local paragraph = paragraphs[i]

        local flag = false
        local i_offset = get_index_offset(sub)
        for i = paragraph.start_i + 1, paragraph.end_i do
            if sub[i].text:find(bi_partition) == nil then
                log(("第 %d 行不包含分隔符: \"%s\""):format(i - i_offset, bi_partition))
                flag = true
            end
            if not is_cn_line(sub[i]) and not is_jp_line(sub[i]) then
                log(("第 %d 行未能找到语言代码(%s/%s)"):format(i - i_offset, cn_str, jp_str))
                flag = true
            end
        end
        if flag then
            aegisub.cancel()
        end

        local part2 = {}
        local part2_comment = table.copy(sub[paragraph.start_i])
        part2_comment.layer = 6
        table.insert(part2, part2_comment)

        local part1_comment = table.copy(sub[paragraph.start_i])
        part1_comment.style = trans_style_name(part1_comment.style)
        part1_comment.text = trans_style_name(part1_comment.text) or part1_comment.text
        part1_comment.layer = 7
        sub[paragraph.start_i] = part1_comment

        for i = paragraph.start_i + 1, paragraph.end_i do
            local l = sub[i]
            local line1, line2 = split_line_text(l)
            table.insert(part2, line1)
            sub[i] = line2
        end

        sub.insert(paragraph.end_i + 1, unpack(part2))
    end
end

-- 全选该段落
local function select_paragraphs(sub, sel)
    local paragraphs = get_paragraphs_by_sel(sub, sel)
    local res = {}
    for i = 1, #paragraphs do
        for j = paragraphs[i].start_i, paragraphs[i].end_i do
            table.insert(res, j)
        end
    end
    return res
end

-- 检查中日对话
local function check_bilingual_dialogue(sub)
    local cn_range, jp_range = get_dialogue_range(sub)
    if cn_range == nil or jp_range == nil then
        log("未能找到中/日对话")
        return
    end
    if cn_range.end_i - cn_range.start_i ~= jp_range.end_i - jp_range.start_i then
        log("中日行数不一致")
        return
    end

    local i_offset = get_index_offset(sub)
    log(("CN: %d ~ %d  JP: %d ~ %d  共 %d 行"):format(
        cn_range.start_i - i_offset, cn_range.end_i - i_offset,
        jp_range.start_i - i_offset, jp_range.end_i - i_offset,
        cn_range.end_i - cn_range.start_i))
    for i = cn_range.start_i + 1, cn_range.end_i do
        local jp_i = jp_range.start_i - cn_range.start_i + i
        local display_cn_i, display_jp_i = i - i_offset, jp_i - i_offset
        local cn_line, jp_line = sub[i], sub[jp_i]

        -- check whether commented
        if cn_line.comment ~= jp_line.comment then
            log(("第 %d 和 %d 行的注释状态不一致"):format(display_cn_i, display_jp_i))
        end

        -- check time
        local st_flag, et_flag = cn_line.start_time ~= jp_line.start_time, cn_line.end_time ~= jp_line.end_time
        if st_flag or et_flag then
            log(("第 %d 和 %d 行的时间不一致：%s %s"):format(display_cn_i, display_jp_i,
                st_flag and "开始" or "", et_flag and "结束" or ""))
        end

        -- check margin
        local ml_flag, mr_flag = cn_line.margin_l ~= jp_line.margin_l, cn_line.margin_r ~= jp_line.margin_r
        if ml_flag or mr_flag then
            log(("第 %d 和 %d 行的边距不一致：%s %s"):format(display_cn_i, display_jp_i,
                ml_flag and "左" or "", mr_flag and "右" or ""))
        end

        -- check punctuations
        local punctuation = { "？", "！", "「", "」", "…" }
        local diff_punctuation = {}
        for _, p in ipairs(punctuation) do
            if count(cn_line.text, p) ~= count(jp_line.text, p) then
                table.insert(diff_punctuation, p)
            end
        end
        if #diff_punctuation > 0 then
            log(("第 %d 和 %d 行的标点不一致：%s"):format(display_cn_i, display_jp_i,
                table.concat(diff_punctuation)))
        end

        -- check tags
        local diff_tags = {}
        local cn_tags = cn_line.text:match("^{(.-)}") or ""
        local jp_tags = jp_line.text:match("^{(.-)}") or ""
        for tag in cn_tags:gmatch("\\[^\\}]+") do
            if not jp_tags:find(escape_pattern(tag)) then
                table.insert(diff_tags, tag)
            end
        end
        for tag in jp_tags:gmatch("\\[^\\}]+") do
            if not cn_tags:find(escape_pattern(tag)) and not in_table(diff_tags, tag) then
                table.insert(diff_tags, tag)
            end
        end
        if #diff_tags > 0 then
            log(("第 %d 和 %d 行的标签不一致：%s"):format(display_cn_i, display_jp_i,
                table.concat(diff_tags, " ")))
        end

        local cn_len = unicode.len(strip_tags(cn_line.text))
        if cn_len > cn_max_length then
            log(("第 %d 行太长(中文): %d > %d"):format(display_cn_i, cn_len, cn_max_length))
        end
        local jp_len = unicode.len(strip_tags(jp_line.text))
        if jp_len > jp_max_length then
            log(("第 %d 行太长(日文): %d > %d"):format(display_jp_i, jp_len, jp_max_length))
        end

        -- check style
        if is_jp_line(cn_line) then
            log("第 " .. display_cn_i .. " 行的样式可能有错")
        end
        if is_cn_line(jp_line) then
            log("第 " .. jp_i " 行的样式可能有错")
        end
        if cn_line.style:gsub(cn_str, jp_str) ~= jp_line.style or jp_line.style:gsub(jp_str, cn_str) ~= cn_line.style then
            log("第 " .. display_cn_i .. " 和 " .. display_jp_i .. " 行的样式不一致")
        end

        -- check spaces
        if cn_line.text:find("[^}]　[^{}]") then
            log("第 " .. display_cn_i .. " 行中文有全角空格")
        end
        if re.find(jp_line.text, "[^0-9a-zA-Z…?!,.} ] [^0-9a-zA-Z]") ~= nil then
            log("第 " .. display_jp_i .. " 行日文有半角空格")
        end
        if cn_line.text:find("^ ") or cn_line.text:find(" $") then
            cn_line.text = trim(cn_line.text)
            sub[i] = cn_line
            log("第 " .. display_cn_i .. " 行首尾有空格，已处理")
        end
        if jp_line.text:find("^ ") or jp_line.text:find(" $") then
            jp_line.text = trim(cn_line.text)
            sub[jp_i] = jp_line
            log("第 " .. display_jp_i .. " 行首尾有空格，已处理")
        end

        -- check line break
        if cn_line.text:find("\\[Nn]") then
            log("第 " .. display_cn_i .. " 行有换行符")
        end
        if jp_line.text:find("\\[Nn]") then
            log("第 " .. display_jp_i .. " 行有换行符")
        end
    end

    log("中日对话检查完毕")
end

-- 检查全文
local function check_full_sub(sub, sel)
    check_bilingual_dialogue(sub)
    local cn_range, jp_range = get_dialogue_range(sub)
    local i_offset = get_index_offset(sub)

    local check_dialogue = true
    if cn_range == nil or jp_range == nil then
        check_dialogue = false
    end

    -- check unrecommended patterns
    for i, line in ipairs(sub) do
        if line.class == "dialogue" then
            for _, pattern in ipairs(unrecommended_patterns) do
                if check_dialogue and pattern.only_dialogue and
                    not (i >= cn_range.start_i and i <= cn_range.end_i or
                        i >= jp_range.start_i and i <= jp_range.end_i) then
                    goto continue
                end
                local matches = {}
                for _, p in ipairs(pattern.patterns) do
                    if pattern.full_regex then
                        local match = re.match(line.text, p)
                        if match then
                            if #match == 1 then
                                table.insert(matches, match[1].str)
                            end
                            for j = 2, #match do
                                table.insert(matches, match[j].str)
                            end
                        end
                    else
                        local match = line.text:match(p)
                        if match then
                            table.insert(matches, match)
                        end
                    end
                end
                if #matches > 0 then
                    log(("第 %d 行: %s (%s)"):format(
                        i - i_offset, pattern.message, table.concat(matches, ", ")))
                end
                ::continue::
            end
        end
    end

    log("全文检查完毕")
end

-- 跳转到对应行
local function jump_to_corresponding_line(sub, sel)
    local paragraphs_map = get_paragraphs_map(sub)

    local min_i, max_i = get_index_offset(sub) + 1, #sub
    local res = {}
    for _, i in ipairs(sel) do
        for name, p in pairs(paragraphs_map) do
            if i >= p.start_i and i <= p.end_i then
                local target_name = trans_style_name(name)
                if not target_name then
                    log(name .. " 未能找到语言代码(CN/JP)")
                    return
                end
                local target_i = paragraphs_map[target_name].start_i - p.start_i + i
                if min_i <= target_i and target_i <= max_i then
                    table.insert(res, target_i)
                end
            end
        end
    end

    return res
end

-- 应用到对应段落
local function apply_to_corresponding_paragragh(sub, sel)
    local all_paragraphs = get_all_paragraphs(sub)
    local paragraphs = get_paragraphs_by_sel(sub, sel, all_paragraphs)
    local paragraphs_sel_map = {}
    for _, p in ipairs(paragraphs) do
        paragraphs_sel_map[p.name] = p
    end
    for _, p in ipairs(paragraphs) do
        local target_name = trans_style_name(p.name)
        if target_name and paragraphs_sel_map[target_name] then
            log("不能同时选中两种语言的段落")
            return
        end
    end

    local paragraphs_map = get_paragraphs_map(sub, all_paragraphs)

    -- 检查段落长度是否一致
    local flag = true
    for _, p in ipairs(paragraphs) do
        if not check_corresponding_paragraph_length(sub, p, paragraphs_map) then
            flag = false
            break
        end
    end
    if not flag then
        log("段落长度不一致，请检查")
        return
    end

    local linked_lines = {}
    for i, line in ipairs(sub) do
        if line.class == "dialogue" and line.effect:find("@linked") then
            table.insert(linked_lines, i)
        end
    end

    for _, p in ipairs(paragraphs) do
        local name = p.name
        for i = p.start_i, p.end_i do
            local target_name = trans_style_name(name)
            local target_i = paragraphs_map[target_name].start_i - p.start_i + i
            local target_line = sub[target_i]
            if sub[i].effect:find("@link") and not sub[i].effect:find("@linked") then
                for _, index in ipairs(linked_lines) do
                    local line = sub[index]
                    if line.start_time == target_line.start_time and line.end_time == target_line.end_time then
                        line.start_time = sub[i].start_time
                        line.end_time = sub[i].end_time
                        sub[index] = line
                    end
                end
            end
            target_line.style = trans_style_name(sub[i].style)
            target_line.start_time = sub[i].start_time
            target_line.end_time = sub[i].end_time
            target_line.margin_l = sub[i].margin_l
            target_line.margin_r = sub[i].margin_r
            target_line.actor = sub[i].actor
            target_line.effect = sub[i].effect
            sub[target_i] = target_line
        end
    end
end

local function split_text_by_ratio(str, delimiter, ratio)
    ratio = ratio or 0.5
    if ratio <= 0 or ratio >= 1 then
        return str, str
    end

    local splits = split(str, delimiter)
    if #splits <= 1 then
        return str, str
    end
    local positions = {}
    local sum = 0
    for _, s in ipairs(splits) do
        sum = sum + #s
        table.insert(positions, sum)
        sum = sum + #delimiter
    end

    local target_pos = math.floor(#str * ratio)
    local closest = positions[1]
    local min_diff = math.abs(closest - target_pos)
    for _, pos in ipairs(positions) do
        local diff = math.abs(pos - target_pos)
        if diff < min_diff then
            closest = pos
            min_diff = diff
        end
    end
    return str:sub(1, closest), str:sub(closest + #delimiter + 1)
end

-- 复制当前激活的行
local function duplicate_line(sub, _, act, split_line)
    local function duplicate(index)
        local line = sub[index]
        local line_copy = table.copy(line)
        if split_line and line.end_time > line.start_time then
            local video_time = aegisub.ms_from_frame(aegisub.project_properties().video_position)
            local ratio = (video_time - line.start_time) / (line.end_time - line.start_time)
            line.text, line_copy.text = split_text_by_ratio(line.text, (is_jp_line(line) and "　" or " "), ratio)
            if ratio > 0 and ratio < 1 then
                line.end_time = video_time
                line_copy.start_time = video_time
            end
        end
        sub.delete(index)
        sub.insert(index, line)
        sub.insert(index + 1, line_copy)
    end

    local all_paragraphs = get_all_paragraphs(sub)
    local paragraphs = get_paragraphs_by_sel(sub, { act }, all_paragraphs)
    if #paragraphs == 0 then
        duplicate(act)
        return { act + 1 }
    end
    local return_sel = act
    local paragraphs_map = get_paragraphs_map(sub, all_paragraphs)
    local p = paragraphs[1]
    local target_name = trans_style_name(p.name)
    if target_name and paragraphs_map[target_name] then
        if check_corresponding_paragraph_length(sub, p, paragraphs_map) then
            local target_i = paragraphs_map[target_name].start_i - p.start_i + act
            if act > target_i then
                duplicate(act)
                duplicate(target_i)
                return_sel = return_sel + 1
            else
                duplicate(target_i)
                duplicate(act)
            end
        else
            log("段落长度不一致，请检查")
            aegisub.cancel()
        end
    else
        sub.insert(act + 1, sub[act])
    end
    return { return_sel }
end

-- 复制当前激活的行，并拆分文本
local function duplicate_line_split(sub, _, act)
    return duplicate_line(sub, _, act, true)
end

-- 下移段落
local function move_paragraphs_down(sub, sel)
    local all_paragraphs = get_all_paragraphs(sub)
    local paragraphs = get_paragraphs_by_sel(sub, sel, all_paragraphs)
    local flag = true -- 选中连续段落
    for i, p in ipairs(paragraphs) do
        if i > 1 then
            if p.start_i ~= paragraphs[i - 1].end_i + 1 then
                flag = false
                break
            end
        end
    end
    if not flag then
        log("只能移动连续的段n")
        return
    end
    local next_paragraph = get_paragraphs_by_sel(sub, { paragraphs[#paragraphs].end_i + 1 }, all_paragraphs)

    if #next_paragraph == 0 then
        log("无法下移了")
        return
    end

    local copy = {}
    local range = {}
    for i = 1, #paragraphs do
        local p = paragraphs[i]
        for j = p.start_i, p.end_i do
            table.insert(copy, sub[j])
            table.insert(range, j)
        end
    end
    local res = {}
    for i = #copy, 1, -1 do
        sub.insert(next_paragraph[1].end_i + 1, copy[i])
        table.insert(res, next_paragraph[1].end_i - i + 1)
    end
    sub.delete(range)
    return res
end

-- 上移段落
local function move_paragraphs_up(sub, sel)
    local all_paragraphs = get_all_paragraphs(sub)
    local paragraphs = get_paragraphs_by_sel(sub, sel, all_paragraphs)
    local flag = true -- 选中连续段落
    for i, p in ipairs(paragraphs) do
        if i > 1 then
            if p.start_i ~= paragraphs[i - 1].end_i + 1 then
                flag = false
                break
            end
        end
    end
    if not flag then
        log("只能移动连续的段落")
        return
    end
    local previous_paragraph = get_paragraphs_by_sel(sub, { paragraphs[1].start_i - 1 }, all_paragraphs)

    if #previous_paragraph == 0 then
        log("无法上移了")
        return
    end

    local copy = {}
    local range = {}
    for i = 1, #paragraphs do
        local p = paragraphs[i]
        for j = p.start_i, p.end_i do
            table.insert(copy, sub[j])
            table.insert(range, j)
        end
    end
    sub.delete(range)
    local res = {}
    for i = #copy, 1, -1 do
        sub.insert(previous_paragraph[1].start_i, copy[i])
        table.insert(res, previous_paragraph[1].start_i + i - 1)
    end
    return res
end

-- 合并行
local function join_lines(sub, sel)
    local function join(sub, t)
        local new_line = sub[t[1]]
        for index, i in ipairs(t) do
            if index > 1 then
                new_line.text = new_line.text .. (is_jp_line(sub[i]) and "　" or " ") .. sub[i].text
            end
            new_line.start_time = math.min(new_line.start_time, sub[i].start_time)
            new_line.end_time = math.max(new_line.end_time, sub[i].end_time)
        end
        return new_line
    end

    local all_paragraphs = get_all_paragraphs(sub)
    local paragraphs_sel = get_paragraphs_by_sel(sub, sel, all_paragraphs)
    local new_line = join(sub, sel)
    -- 处理普通合并
    if #paragraphs_sel == 0 then
        sub.delete(sel)
        sub.insert(sel[1], new_line)
        return { sel[1] }
    end
    local paragraphs_sel_map = {}
    for _, p in ipairs(paragraphs_sel) do
        paragraphs_sel_map[p.name] = p
    end
    local paragraphs_map = get_paragraphs_map(sub, all_paragraphs)
    local paragraph_mode = false -- 有对应的段落，且未选中
    for _, p in ipairs(paragraphs_sel) do
        local target_name = trans_style_name(p.name)
        if target_name and paragraphs_map[target_name] and
            not paragraphs_sel_map[target_name] and
            check_corresponding_paragraph_length(sub, p, paragraphs_map) then
            paragraph_mode = true
        end
    end
    if not paragraph_mode then
        sub.delete(sel)
        sub.insert(sel[1], new_line)
        return { sel[1] }
    else
        local target_sel = {}
        for _, i in ipairs(sel) do
            for name, p in pairs(paragraphs_map) do
                if i >= p.start_i and i <= p.end_i then
                    local target_name = trans_style_name(name)
                    local target_i = paragraphs_map[target_name].start_i - p.start_i + i
                    table.insert(target_sel, target_i)
                end
            end
        end

        local new_line_trans = join(sub, target_sel)
        if target_sel[1] > sel[1] then
            sub.delete(target_sel)
            sub.insert(target_sel[1], new_line_trans)
            sub.delete(sel)
            sub.insert(sel[1], new_line)
            return { sel[1] }
        else
            sub.delete(sel)
            sub.insert(sel[1], new_line)
            sub.delete(target_sel)
            sub.insert(target_sel[1], new_line_trans)
            return { sel[1] - #sel + 1 }
        end
    end
end

-- 跳转到上一个段落
local function jump_to_previous_paragraph(sub, sel)
    local all_paragraphs = get_all_paragraphs(sub)
    local first_paragraph = get_paragraphs_by_sel(sub, { sel[1] }, all_paragraphs)[1]
    local previous_paragraph = get_paragraphs_by_sel(sub, { first_paragraph.start_i - 1 }, all_paragraphs)
    if #previous_paragraph == 0 then
        return { first_paragraph.start_i }
    else
        return { previous_paragraph[1].start_i }
    end
end

-- 跳转到下一个段落
local function jump_to_next_paragraph(sub, sel)
    local all_paragraphs = get_all_paragraphs(sub)
    local last_paragraphs = get_paragraphs_by_sel(sub, { sel[#sel] }, all_paragraphs)[1]
    local next_paragraph = get_paragraphs_by_sel(sub, { last_paragraphs.end_i + 1 }, all_paragraphs)
    if #next_paragraph == 0 then
        return { last_paragraphs.end_i }
    else
        return { next_paragraph[1].start_i }
    end
end

-- 是否选中段落
local function check_paragraph_name(sub, sel)
    if #sel == 0 then
        return false
    end
    for i = sel[1], 1, -1 do
        if sub[i].class == "dialogue" and sub[i].comment and sub[i].text:match(paragraph_pattern()) then
            return true
        end
    end
    return false
end

-- 是否选中段落
local function check_next_paragraph_name(sub, sel)
    if #sel == 0 then
        return false
    end
    for i = sel[1], #sub do
        if sub[i].class == "dialogue" and sub[i].comment and sub[i].text:match(paragraph_pattern()) then
            return true
        end
    end
    return false
end

-- 是否有中日对话段落
local function has_bilingual_dialogue(sub)
    local cn_flag, jp_flag = false, false
    for _, line in ipairs(sub) do
        if line.class == "dialogue" then
            if line.comment and line.text:match(paragraph_pattern(cn_paragraph_name)) then
                cn_flag = true
            elseif line.comment and line.text:match(paragraph_pattern(jp_paragraph_name)) then
                jp_flag = true
            end
            if cn_flag and jp_flag then
                return true
            end
        end
    end
    return false
end

-- register macro
aegisub.register_macro(script_name .. "/Apply to Corresponding Para", "应用到对应段落",
    apply_to_corresponding_paragragh, check_paragraph_name)
aegisub.register_macro(script_name .. "/Check Bilingual Dialogue", "检查对话中日轴",
    check_bilingual_dialogue, has_bilingual_dialogue)
aegisub.register_macro(script_name .. "/Check Full Sub", "检查全文",
    check_full_sub)
aegisub.register_macro(script_name .. "/Duplicate Active Line", "复制当前激活行",
    duplicate_line)
aegisub.register_macro(script_name .. "/Join Lines (Bilingual)", "合并行",
    join_lines, function(_, sel) return #sel > 1 end)
aegisub.register_macro(script_name .. "/Jump to Corresponding Line", "跳转到对应行",
    jump_to_corresponding_line, check_paragraph_name)
aegisub.register_macro(script_name .. "/Jump to Next Para", "跳转到下一个段落",
    jump_to_next_paragraph, check_next_paragraph_name)
aegisub.register_macro(script_name .. "/Jump to Prev Para", "跳转到上一个段落",
    jump_to_previous_paragraph, check_paragraph_name)
aegisub.register_macro(script_name .. "/Move Paras Down", "下移选定段落",
    move_paragraphs_down, check_paragraph_name)
aegisub.register_macro(script_name .. "/Move Paras Up", "上移选定段落",
    move_paragraphs_up, check_paragraph_name)
aegisub.register_macro(script_name .. "/Select Paras", "全选该段落",
    select_paragraphs, check_paragraph_name)
aegisub.register_macro(script_name .. "/Split Active Line At Current Frame", "在当前帧位置拆分行",
    duplicate_line_split)
aegisub.register_macro(script_name .. "/Split Bilingual Paras", "拆分选定段落的中日轴",
    split_bilingual_paragraphs, check_paragraph_name)
