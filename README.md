# Aegisub-Scripts

## MarginAdjuster

调整视觉不居中的字幕行

- **Margin Adjuster/Adjust Dialogues:** 调整对话[段落](#解释)，会跳过带有 `\pos` 和 `\move` 的行
- **Margin Adjuster/Adjust Paragraphs:** 通过对话框指定要调整的段落，跳过带有 `\pos` 和 `\move` 的行
- **Margin Adjuster/Adjust Selection:** 选中字幕，调整其边距
- **Margin Adjuster/Adjust Selection using `\pos`:** 使用 `\pos` 标签调整选中字幕的边距

## MingYSub-Scripts

适用于 MingYSub 的实用字幕处理工具

### 解释

段落的开始定义为：`------ NAME ------`（需要是注释行，至少 6 个 `-`，后可接任意字符；例：`------ OPCN ------ ABC`）

下面的设置可以通过在代码中修改。
- 中文样式：`CN` （样式名称带有 `CN` 视为中文样式）
- 日文样式：`JP` （样式名称带有 `JP` 视为日文样式）
- 中文段落名：`Dialogue CN`
- 日文段落名：`Dialogue JP`
- 中日分隔符：`。`

如果要使两个段落对应，需要设置一个的段落名为 `XXCNYY`，另一个的段落名为 `XXJPYY` （或是自己定义的中日样式）

### Apply to Corresponding Para

应用到对应段落

**功能:** 把注释状态、时间、样式、边距、说话人、特效设置到对应段落

**要求:** 存在对应段落，且长度一致

### Check Bilingual Dialogue

检查对话中日轴，包括时间、标点、标签、样式、边距、空格、换行符

**要求:** 存在对话中日段落，且长度一致

### Copy Line

复制当前激活行，如果有对应段落则会尝试复制对应行。

**要求:** 如果希望在段落上使用，需要存在对应段落，且长度一致

### Check Full Sub

检查全文。除检查对话中日轴外，还会检查全文的用词。可自行修改代码中的 `unrecommended_patterns` 变量。

### Join Lines (Bilingual)

可以代替 Aegisub 的合并行，如果有对应段落则同时合并对应段落的几行，否则和原始的合并行一样

**要求:** 如果要同时合并对应段落的几行，需要存在对应段落，且长度一致，不能同时选择中日段落

### Jump to Corresponding Line

跳转到对应段落的对应行

**要求:** 存在对应段落

### Jump to Next Para

跳转到下一个段落

### Jump to Prev Para

跳转到上一个段落

### Move Paras Down

下移选定段落

**要求** 需要选中连续的段落（选中每个段落的一行或多行）

### Move Paras Up

上移选定段落

**要求** 需要选中连续的段落（选中每个段落的一行或多行）

### Select Paras

全选该段落

**要求** 选中段落中的一行或多行

### Split Bilingual Lines

拆分选定行的中日轴，不推荐使用

**要求** 选中行必须包含特定的换行符

### Split Bilingual Paras

拆分选定段落的中日轴

**要求** 选中段落必须包含特定的分割符

