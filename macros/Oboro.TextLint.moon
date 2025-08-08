export script_name = "Text Lint"
export script_description = "Lint subtitles based on specific rules."
export script_author = "Oborozuki"
export script_version = "0.1.2"
export script_namespace = "Oboro.TextLint"

haveDepCtrl, DependencyControl = pcall require, "l0.DependencyControl"
local depctrl, aconfig, math, os, re
if haveDepCtrl
	depctrl = DependencyControl {
		feed: "https://raw.githubusercontent.com/Akatmks/Akatsumekusa-Aegisub-Scripts/master/DependencyControl.json"
		{ "aka.config", "math", "os", "re" }
	}
	aconfig, math, os, re = depctrl\requireModules!
else
	aconfig = require "aka.config"
	math = require "math"
	os = require "os"
	re = require "aegisub.re"

round = (num, decimal = 3) ->
	multiplier = 10 ^ decimal
	return math.floor(num * multiplier + 0.5) / multiplier

matchCondition = (line, conditionGroup) ->
	for { :field, :pattern, :mode } in *conditionGroup.filters
		value = line[field]
		matched = pattern\match value
		if conditionGroup.type == "or"
			return true if (mode != "not_match" and matched) or (mode == "not_match" and not matched)
		else
			return false if (mode != "not_match" and not matched) or (mode == "not_match" and matched)
	return if conditionGroup.type == "or" then false else true

shouldSkip = (line, condition) ->
	return true if condition.skip_comments and line.comment
	return false unless condition.skip
	for group in *condition.skip
		return true if matchCondition line, group
	return false

shouldMatch = (line, condition) ->
	return true unless condition.match and #condition.match > 0
	for group in *condition.match
		return true if matchCondition line, group
	return false

loadPresets = ->
	with aconfig.read_config script_namespace, "presets"
		presets = \unwrapOr { presets: { default: {} }, current: "default" }
		if presets.current == nil or not presets.presets[presets.current]
			presets.current = "default"
		if presets.presets.default == nil
			presets.presets.default = {}
		return presets

loadLintMap = (filename) ->
	with aconfig.read_config script_namespace, filename
		lintMap = \unwrapOr {}
		return lintMap

processCondition = (condition) ->
	process = (groups) ->
		newGroups = {}
		for group in *groups
			if group.filters and #group.filters > 0
				newFilters = {}
				for filter in *group.filters
					flags = [ re[flag] for flag in *(filter.flags or {}) when re[flag] ]
					table.insert newFilters, {
						field: filter.field or "text"
						pattern: re.compile filter.pattern, unpack flags
						mode: filter.mode
					}
				table.insert newGroups, {
					type: group.type
					filters: newFilters
				}
		return newGroups

	condition.skip = process condition.skip or {}
	condition.match = process condition.match or {}
	return condition

loadRules = ->
	presets = loadPresets!
	preset = presets.presets[presets.current] or {}
	table.sort preset
	rulesInFile = {}
	success = true
	for ruleName in *preset
		filename, rule = ruleName\match "^(.-)/(.*)$"
		unless filename and rule
			aegisub.log "Error: Invalid rule format '#{ruleName}'. Expected 'filename/rule_name'.\n"
			success = false
			continue
		rulesInFile[filename] = {} unless rulesInFile[filename]
		table.insert rulesInFile[filename], rule
	unless success
		aegisub.log "Please check the presets.\n"
		aegisub.cancel!

	rules = {}
	for filename, ruleNames in pairs rulesInFile
		lintMap = loadLintMap filename
		currentRules = {}
		for ruleName in *ruleNames
			if ruleName == "*"
				for k, v in pairs lintMap
					currentRules[k] = v
			else if lintMap[ruleName]
				currentRules[ruleName] = lintMap[ruleName]
			else
				aegisub.log "Warning: Rule '#{ruleName}' not found in #{filename}.\n"
		for ruleName, rule in pairs currentRules
			flags = [ re[flag] for flag in *(rule.flags or {}) when re[flag] ]
			table.insert rules, {
				namespace: "#{filename}/#{ruleName}",
				name: rule.name or ruleName
				patterns: [ re.compile pattern, unpack flags for pattern in *rule.patterns ]
				field: rule.field or "text"
				message: rule.message or "No message provided"
				severity: rule.severity or "Warning"
				condition: processCondition rule.condition or {}
			}
	return { name: presets.current, rules: preset }, rules


logLint = (severity, lintName, field, message) -> aegisub.log "[#{severity}] #{lintName} (#{field}): #{message}\n"

logLineInfo = (first, last, text) ->
	text = "(empty)" if #text == 0
	index = if first == last then first else "#{first}-#{last}"
	aegisub.log "- Line #{index}: #{text}\n"

logDevidingLine = -> aegisub.log "-----------------------------------------\n"

lint = (sub) ->
	startTime = os.clock!

	preset, rules = loadRules!
	aegisub.log "Preset: #{preset.name}\nRules:\n"
	for rule in *rules
		aegisub.log "- #{rule.namespace}\n"
	logDevidingLine!

	indexOffset = 0
	n = #sub
	subCopy = {}
	for i = 1, n
		line = sub[i]
		if line.class != "dialogue"
			indexOffset = i
		else
			line.text_stripped = line.text\gsub "%{.-%}", ""
			subCopy[i - indexOffset] = line
	sel = {}
	disableAllLintPattern = re.compile "(^|;)\\s*lint-disable\\s*(;|$)", re.NOSUB
	for { :namespace, :name, :field, :patterns, :message, :severity, :condition } in *rules
		count = 0
		logged = false
		startIndex = nil
		lastMatch = nil
		for i, line in pairs subCopy
			disableCurLintPattern = re.compile "(^|;)\\s*lint-disable\\s*:([^;]*,)?\\s*(\\Q#{namespace}\\E)\\s*(,[^;]*)?(;|$)", re.NOSUB
			continue if disableAllLintPattern\match(line.effect) or disableCurLintPattern\match(line.effect)
			continue unless shouldMatch line, condition
			continue if shouldSkip line, condition
			text = line[field]
			currMatches = {}
			for pattern in *patterns
				if match = pattern\match text
					table.insert currMatches, match[1].str
					count += 1
			if #currMatches > 0
				logLint severity, name, field, message unless logged
				logged = true
				table.insert sel, i + indexOffset
				currMatch = table.concat currMatches, ", "
				startIndex = i if startIndex == nil
				if lastMatch and lastMatch != currMatch
					logLineInfo startIndex, i - 1, lastMatch
				else
					lastMatch = currMatch
				startIndex = i if lastMatch != currMatch
			else
				if lastMatch
					logLineInfo startIndex, i - 1, lastMatch
					startIndex = nil
				lastMatch = nil
		if lastMatch
			logLineInfo startIndex, n - indexOffset, lastMatch
		if count > 0
			aegisub.log "Found #{count} occurrences in #{n - indexOffset} lines.\n"
			logDevidingLine!
	endTime = os.clock!
	aegisub.log "Linting completed with #{#rules} rules in #{round endTime - startTime} seconds.\n"
	return sel

dialogWarn = (message) -> aegisub.dialog.display { { class: "label", label: message } }, { ok: "&OK" }

configPresets = ->
	presets = loadPresets!
	currentPreset = presets.current
	interface = {
		{ class: "label", label: "Choose Preset", x: 0, y: 0 },
		{ class: "dropdown", name: "preset", items: [ k for k in pairs presets.presets ], value: presets.current, x: 1, y: 0, width: 25 }
	}
	if presets.presets[presets.current]
		table.insert interface, { class: "label", label: "Preset Rules", x: 0, y: 1 }
		table.insert interface, { class: "checkbox", name: "recreate", label: "&Recreate Interface after saved", x: 1, y: 1 }
		table.sort presets.presets[presets.current]
		for i, ruleName in ipairs presets.presets[presets.current]
			table.insert interface, { class: "label", label: "Rule #{i}", x: 0, y: 1 + i }
			table.insert interface, { class: "edit", name: "rule#{i}", value: ruleName, x: 1, y: 1 + i, width: 25 }
		y = (#interface - 2) / 2
		for i = 1, 3
			table.insert interface, { class: "label", label: "New Rule", x: 0, y: y + i }
			table.insert interface, { class: "edit", name: "rule#{y + i - 1}", x: 1, y: y + i, width: 25 }

	button, result = aegisub.dialog.display interface,
		{ "&Save/Reload", "&New Preset", "&Del Preset", "&Cancel" },
		{ ok: "&Save/Reload", cancel: "&Cancel" }
	return unless button
	newPresets = presets
	recreateInterface = result.recreate
	if button == "&Save/Reload"
		newPresets.presets[currentPreset] = [ v for k, v in pairs result when v != "" and k\match "^rule" ]
		if currentPreset != result.preset
			presets.current = result.preset
			recreateInterface = true
		recreateInterface = true if currentPreset != result.preset
	else if button == "&New Preset"
		button, result = aegisub.dialog.display {
			{ class: "label", label: "New Preset Name", x: 0, y: 0 },
			{ class: "edit", name: "presetName", x: 0, y: 1, width: 30 }
		}
		recreateInterface = true
		if button
			success = true
			if result.presetName == ""
				dialogWarn "Preset name cannot be empty."
				success = false
			else if presets.presets[result.presetName]
				dialogWarn "Preset name already exists."
				success = false
			if success
				newPresets.presets[result.presetName] = {}
				newPresets.current = result.presetName
	else if button == "&Del Preset"
		if result.preset == "default"
			dialogWarn "Cannot delete the default preset."
		else
			newPresets.presets[result.preset] = nil
			newPresets.current = "default"
		recreateInterface = true

	aconfig.write_config "#{script_namespace}/presets", newPresets
	configPresets! if recreateInterface

if haveDepCtrl
	depctrl\registerMacros {
		{ "Config Presets", "Config Presets", configPresets }
		{ "Lint", script_description, lint }
	}
else
	aegisub.register_macro "#{script_name}/Config Presets", "Config Presets", configPresets
	aegisub.register_macro "#{script_name}/Lint", script_description, lint
