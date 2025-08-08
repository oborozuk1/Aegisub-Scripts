# Aegisub-Scripts

DepCtrl Feed: `https://raw.githubusercontent.com/oborozuk1/Aegisub-Scripts/main/DependencyControl.json`

## Margin Adjuster

可用 DepCtrl 安装

调整视觉不居中的字幕行

- **Margin Adjuster/Adjust Dialogues:** 调整对话[段落](#解释)，会跳过带有 `\pos` 和 `\move` 的行
- **Margin Adjuster/Adjust Paragraphs:** 通过对话框指定要调整的段落，跳过带有 `\pos` 和 `\move` 的行
- **Margin Adjuster/Adjust Selection:** 选中字幕，调整其边距
- **Margin Adjuster/Adjust Selection using `\pos`:** 使用 `\pos` 标签调整选中字幕的边距

## Text Lint

可用 DepCtrl 安装

基于正则表达式检查字幕的文本。目前需要手动编写预设规则，放在配置目录下，格式参见[例子](./snippets/Oboro.TextLint/Example.json)。

在 Text Lint > Config Presets 里设置预设，规则的格式为：`filename/rule_name`（例如：`Example/EmptyLine`，`filename/*` 代表文件内的所有规则）。

在特效栏里添加 `lint-disable` 禁用此行所有检查，添加 `lint-disable: A/B, C/D` 禁用此行指定规则检查。

## MingYSub Macro Collection

请手动安装 [MingYSub-Macro-Collection.moon](./macros/MingYSub-Macro-Collection.moon)

适用于 MingYSub 的实用字幕处理工具

**注意：正在重构…**

### 解释

段落的开始定义为：`------ NAME ------`（需要是注释行，至少 6 个 `-`，后可接任意字符；例：`------ OPCN ------ ABC`）

下面的设置可以通过在代码中修改。

- 中文样式：`CN` （样式名称带有 `CN` 视为中文样式）
- 日文样式：`JP` （样式名称带有 `JP` 视为日文样式）
- 中文对话段落名：`Dialogue CN`
- 日文对话段落名：`Dialogue JP`
- 中日分隔符：`。`

如果要使两个段落对应，需要设置一个的段落名为 `XXCNYY`，另一个的段落名为 `XXJPYY` （或是自己定义的中日样式）

### Apply to Corresponding Para

把注释状态、时间、样式、边距、说话人、特效设置到对应段落

**要求:** 存在对应段落，且长度一致

<!-- ### Check Bilingual Dialogue

检查对话中日轴，包括时间、标点、标签、样式、边距、空格、换行符。

**要求:** 存在对话中日段落，且长度一致 -->

<!-- ### Check Full Sub

检查全文。除检查对话中日轴外，还会检查全文的用词。可自行修改代码中的 `unrecommended_patterns` 变量。 -->

### Duplicate Selection

复制选中行，如果有对应段落则会尝试复制对应行。

**要求:** 如果希望在对应段落上使用，需要存在对应段落，且长度一致

### Join Lines (Smart)

可以代替 Aegisub 的合并行。如果有对应段落则同时合并对应段落的几行，否则和原始的合并行一样。

**要求:** 如果要同时合并对应段落的几行，需要存在对应段落，且长度一致，不能同时选择中日段落

### Jump to Corresponding Line

跳转到对应段落的对应行。

**要求:** 存在对应段落

### Jump to Next Para

跳转到下一个段落。

### Jump to Prev Para

跳转到上一个段落。

### Move Paras Down

下移选定段落。

### Move Paras Up

上移选定段落。

### Select Paras

全选该段落

**要求:** 选中段落中的一行或多行

### Split Active Line At Current Frame

在当前帧位置拆分行，如果有对应段落则会尝试拆分对应行。

### Split Bilingual Paras

拆分选定段落的中日轴。

如果是「{中文}{分隔符}{日文}」的形式，请设置这一段落为中文段落；反之设置为日文段落。

**要求:** 选中段落必须包含特定的分割符，注意一行里分割符只能出现一次
