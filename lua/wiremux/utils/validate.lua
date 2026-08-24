local placeholder = require("wiremux.placeholder")

local M = {}

local valid = {
	behaviors = { last = true, pick = true, all = true },
	resolve_modes = { auto = true, instances = true, definitions = true, all = true },
	kinds = { pane = true, window = true },
	splits = { horizontal = true, vertical = true },
	split_modes = { before = true, after = true },
	log_levels = { off = true, error = true, warn = true, info = true, debug = true },
	compose_close_behaviors = { ask = true, hide = true, discard = true },
	compose_new_payload = { ask = true, keep = true, replace = true, append = true },
	compose_styles = { minimal = true },
	compose_borders = { none = true, single = true, double = true, rounded = true, solid = true, shadow = true },
	keymap_modes = {
		[""] = true,
		n = true,
		v = true,
		x = true,
		s = true,
		o = true,
		i = true,
		l = true,
		c = true,
		t = true,
		["!"] = true,
	},
	keymap_actions = {
		send = true,
		close = true,
		discard = true,
		files = true,
		delete_page = true,
		preview_placeholder = true,
		previous = true,
		next = true,
	},
}

local compose_session_fields = {
	width = true,
	height = true,
	title = true,
	border = true,
	style = true,
	close_behavior = true,
	on_new_payload = true,
	wo = true,
	keymaps = true,
}

---@class wiremux.Error
---@field path string
---@field message string

---@param path string
---@param message string
---@return wiremux.Error
local function validation_error(path, message)
	return { path = path, message = message }
end

---Check set membership, treating nil as valid, and format the shared "use: ..." message.
---@param value any
---@param valid_set table<string, true>
---@param name string
---@param context? string
---@return string? error
local function validate_field(value, valid_set, name, context)
	if value == nil or valid_set[value] ~= nil then
		return nil
	end

	return string.format(
		"invalid %s '%s'%s, use: %s",
		name,
		tostring(value),
		context and " " .. context or "",
		table.concat(vim.fn.sort(vim.tbl_keys(valid_set)), ", ")
	)
end

---@param picker string|function|table|nil
---@return string? error
local function validate_picker(picker)
	if picker == nil then
		return nil
	end

	local picker_type = type(picker)
	if picker_type == "table" then
		if picker.adapter ~= nil then
			local adapter_type = type(picker.adapter)
			if adapter_type ~= "string" and adapter_type ~= "function" then
				return string.format("picker.adapter must be string or function, got %s", adapter_type)
			end
			if adapter_type == "string" then
				local adapter_ok = pcall(require, "wiremux.picker." .. picker.adapter)
				if not adapter_ok then
					return string.format("invalid picker.adapter '%s', adapter not found", picker.adapter)
				end
			end
		end
		return nil
	elseif picker_type ~= "string" and picker_type ~= "function" then
		return string.format("picker must be string, function, or table, got %s", picker_type)
	end

	if picker_type == "string" then
		local adapter_ok = pcall(require, "wiremux.picker." .. picker)
		if not adapter_ok then
			return string.format("invalid picker '%s', adapter not found", picker)
		end
		return string.format(
			"picker = '%s' is no longer supported. Use picker = { adapter = '%s' } instead",
			picker,
			picker
		)
	end

	return nil
end

---@param resolvers table|nil
---@return string[] errors
local function validate_resolvers(resolvers)
	local errors = {}

	if resolvers == nil then
		return errors
	end
	if type(resolvers) ~= "table" then
		table.insert(errors, string.format("context.resolvers must be table, got %s", type(resolvers)))
		return errors
	end

	for name, resolver in pairs(resolvers) do
		if not placeholder.is_valid_name(name) then
			table.insert(
				errors,
				string.format(
					"context resolver name '%s' must match %s",
					tostring(name),
					placeholder.validation_pattern
				)
			)
		elseif type(resolver) ~= "function" then
			table.insert(
				errors,
				string.format("context resolver '%s' is not a function (got %s)", name, type(resolver))
			)
		end
	end

	return errors
end

---@param kind "pane"|"window"|("pane"|"window")[]|nil
---@param target_name string
---@return string? error
local function validate_kind(kind, target_name)
	if kind == nil then
		return nil
	end
	if type(kind) == "string" then
		if valid.kinds[kind] then
			return nil
		end
		return string.format("invalid kind '%s' for target '%s', use: pane, window", kind, target_name)
	end
	if type(kind) == "table" then
		if #kind == 0 then
			return string.format("kind table for target '%s' cannot be empty", target_name)
		end
		if #kind == 1 then
			return string.format(
				"kind table for target '%s' has a single value, use kind = '%s' instead",
				target_name,
				tostring(kind[1])
			)
		end
		local seen = {}
		for _, value in ipairs(kind) do
			if type(value) ~= "string" or not valid.kinds[value] then
				return string.format(
					"invalid kind value '%s' in table for target '%s', use: pane, window",
					tostring(value),
					target_name
				)
			end
			if seen[value] then
				return string.format("duplicate kind '%s' in table for target '%s'", value, target_name)
			end
			seen[value] = true
		end
		return nil
	end
	return string.format("kind for target '%s' must be string or table, got %s", target_name, type(kind))
end

---@param mode any
---@return boolean
local function valid_keymap_mode(mode)
	if type(mode) == "string" then
		return valid.keymap_modes[mode] == true
	end
	if type(mode) ~= "table" or not vim.islist(mode) or #mode == 0 then
		return false
	end
	for _, entry in ipairs(mode) do
		if type(entry) ~= "string" or not valid.keymap_modes[entry] then
			return false
		end
	end
	return true
end

---@param keymap any
---@param path string
---@return wiremux.Error[]
local function validate_keymap(keymap, path)
	local errors = {}
	if type(keymap) ~= "table" then
		return { validation_error(path, string.format("%s must be a keymap table, got %s", path, type(keymap))) }
	end
	if type(keymap[1]) ~= "string" or keymap[1] == "" then
		table.insert(errors, validation_error(path .. "[1]", path .. "[1] must be a non-empty key string"))
	end
	if keymap.mode ~= nil and not valid_keymap_mode(keymap.mode) then
		table.insert(errors, validation_error(path .. ".mode", path .. ".mode contains an invalid mapping mode"))
	end
	return errors
end

---@param entry any
---@param path string
---@return wiremux.Error[]
local function validate_keymap_entry(entry, path)
	if type(entry) ~= "table" then
		return { validation_error(path, string.format("%s must be a keymap table or list, got %s", path, type(entry))) }
	end
	if next(entry) == nil then
		return {}
	end
	if type(entry[1]) == "string" then
		return validate_keymap(entry, path)
	end
	if not vim.islist(entry) then
		return { validation_error(path, path .. " must be a keymap table or list") }
	end

	local errors = {}
	for index, keymap in ipairs(entry) do
		vim.list_extend(errors, validate_keymap(keymap, string.format("%s[%d]", path, index)))
	end
	return errors
end

---@param keymaps any
---@param path string
---@return wiremux.Error[]
local function validate_keymaps(keymaps, path)
	if type(keymaps) ~= "table" then
		return { validation_error(path, string.format("%s must be a table, got %s", path, type(keymaps))) }
	end

	local errors = {}
	for action, entry in pairs(keymaps) do
		if not valid.keymap_actions[action] then
			table.insert(
				errors,
				validation_error(
					path .. "." .. tostring(action),
					string.format("unknown compose keymap action '%s' for %s", tostring(action), path)
				)
			)
		else
			vim.list_extend(errors, validate_keymap_entry(entry, path .. "." .. action))
		end
	end
	return errors
end

---@param border any
---@return boolean
local function valid_border(border)
	if type(border) == "string" then
		return valid.compose_borders[border] == true
	end
	if type(border) ~= "table" or not vim.islist(border) then
		return false
	end
	local valid_lengths = { [1] = true, [2] = true, [4] = true, [8] = true }
	if not valid_lengths[#border] then
		return false
	end
	for _, segment in ipairs(border) do
		if type(segment) ~= "string" then
			return false
		end
	end
	return true
end

---Validate and copy a partial compose option table.
---@param options any
---@param path? string
---@return table normalized
---@return wiremux.Error[] errors
function M.compose_options(options, path)
	path = path or "compose"
	if type(options) ~= "table" then
		return {}, {
			validation_error(path, string.format("%s must be a boolean or table, got %s", path, type(options))),
		}
	end

	local normalized = {}
	local errors = {}
	for field, value in pairs(options) do
		local field_path = path .. "." .. tostring(field)
		if not compose_session_fields[field] then
			table.insert(
				errors,
				validation_error(field_path, string.format("unknown compose option '%s' for %s", tostring(field), path))
			)
		elseif field == "width" or field == "height" then
			if type(value) == "number" and value >= 0.1 and value <= 1 then
				normalized[field] = value
			else
				table.insert(errors, validation_error(field_path, field_path .. " must be a number between 0.1 and 1"))
			end
		elseif field == "title" then
			if type(value) == "string" then
				normalized.title = value
			else
				table.insert(errors, validation_error(field_path, field_path .. " must be a string"))
			end
		elseif field == "border" then
			if valid_border(value) then
				normalized.border = vim.deepcopy(value)
			else
				table.insert(
					errors,
					validation_error(field_path, field_path .. " must be a valid border name or segment list")
				)
			end
		elseif field == "style" then
			local message = validate_field(value, valid.compose_styles, "style", "for " .. path)
			if message then
				table.insert(errors, validation_error(field_path, message))
			else
				normalized.style = value
			end
		elseif field == "close_behavior" then
			local message = validate_field(value, valid.compose_close_behaviors, "close_behavior", "for " .. path)
			if message then
				table.insert(errors, validation_error(field_path, message))
			else
				normalized.close_behavior = value
			end
		elseif field == "on_new_payload" then
			local message = validate_field(value, valid.compose_new_payload, "on_new_payload", "for " .. path)
			if message then
				table.insert(errors, validation_error(field_path, message))
			else
				normalized.on_new_payload = value
			end
		elseif field == "wo" then
			if type(value) == "table" then
				normalized.wo = vim.deepcopy(value)
			else
				table.insert(errors, validation_error(field_path, field_path .. " must be a table"))
			end
		elseif field == "keymaps" then
			local keymap_errors = validate_keymaps(value, field_path)
			vim.list_extend(errors, keymap_errors)
			if #keymap_errors == 0 then
				normalized.keymaps = vim.deepcopy(value)
			end
		end
	end
	return normalized, errors
end

---@param base table
---@param overrides table
---@return table
local function merge_compose(base, overrides)
	local merged = vim.tbl_deep_extend("force", {}, base, overrides)
	if type(overrides.keymaps) == "table" and type(merged.keymaps) == "table" then
		for action, entry in pairs(overrides.keymaps) do
			if type(entry) == "table" and next(entry) == nil then
				merged.keymaps[action] = {}
			end
		end
	end
	return merged
end

---Normalize global ui.compose config, falling back field-by-field to defaults.
---@param options any
---@param defaults wiremux.config.ComposeSessionConfig
---@return wiremux.config.ComposeSessionConfig normalized
---@return wiremux.Error[] errors
function M.normalize_global_compose(options, defaults)
	if options == nil then
		return vim.deepcopy(defaults), {}
	end
	if type(options) ~= "table" then
		return vim.deepcopy(defaults),
			{
				validation_error("ui.compose", string.format("ui.compose must be a table, got %s", type(options))),
			}
	end

	local normalized, errors = M.compose_options(options, "ui.compose")
	return merge_compose(defaults, normalized), errors
end

---Normalize the global actions.send.compose default.
---@param value any
---@param default boolean|table
---@return boolean|table normalized
---@return wiremux.Error[] errors
function M.normalize_action_compose(value, default)
	if value == nil then
		return vim.deepcopy(default), {}
	end
	if type(value) == "boolean" then
		return value, {}
	end
	if type(value) ~= "table" then
		return vim.deepcopy(default),
			{
				validation_error(
					"actions.send.compose",
					string.format("actions.send.compose must be a boolean or table, got %s", type(value))
				),
			}
	end

	local normalized, errors = M.compose_options(value, "actions.send.compose")
	return normalized, errors
end

---Resolve one selected runtime compose value into a complete session-only config.
---@param global_compose wiremux.config.ComposeSessionConfig
---@param value any
---@param path string
---@return wiremux.config.ComposeSessionConfig? config
---@return wiremux.Error[] errors
function M.resolve_compose(global_compose, value, path)
	if value == nil or value == false then
		return nil, {}
	end
	if value == true then
		value = {}
	elseif type(value) ~= "table" then
		return nil,
			{
				validation_error(path, string.format("%s must be a boolean or table, got %s", path, type(value))),
			}
	end

	local overrides, errors = M.compose_options(value, path)
	if #errors > 0 then
		return nil, errors
	end
	return merge_compose(global_compose, overrides), {}
end

---@param errors wiremux.Error[]
---@return string[]
function M.error_messages(errors)
	local messages = {}
	for _, err in ipairs(errors) do
		table.insert(messages, err.message)
	end
	return messages
end

---@param opts table
---@return string[] errors List of validation errors (empty if no errors)
function M.validate(opts)
	local errors = {}
	local function collect_error(err)
		if err then
			table.insert(errors, err)
		end
	end

	collect_error(validate_field(opts.log_level, valid.log_levels, "log_level"))

	for name, def in pairs(vim.tbl_get(opts, "targets", "definitions") or {}) do
		collect_error(validate_kind(def.kind, name))
		collect_error(validate_field(def.split, valid.splits, "split", "for target '" .. name .. "'"))
		collect_error(validate_field(def.split_mode, valid.split_modes, "split_mode", "for target '" .. name .. "'"))
	end

	for action, cfg in pairs(opts.actions or {}) do
		collect_error(validate_field(cfg.behavior, valid.behaviors, "behavior", "for action '" .. action .. "'"))
	end

	collect_error(validate_picker(opts.picker))
	vim.list_extend(errors, validate_resolvers(vim.tbl_get(opts, "context", "resolvers")))
	return errors
end

---Accepted value sets, shared with callers that validate the same options. Read-only.
M.valid = valid

---@param expected type
---@return fun(value: any): boolean
local function optional_type(expected)
	return function(value)
		return value == nil or type(value) == expected
	end
end

---@param valid_set table<string, true>
---@return fun(value: any): boolean
local function member_of(valid_set)
	return function(value)
		return valid_set[value] ~= nil
	end
end

---@param value any
---@return boolean
local function is_keys(value)
	if value == nil or type(value) == "string" then
		return true
	end
	if type(value) ~= "table" or not vim.islist(value) then
		return false
	end
	for _, key in ipairs(value) do
		if type(key) ~= "string" then
			return false
		end
	end
	return true
end

---@param value any
---@return boolean
local function is_filter(value)
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	return (value.instances == nil or type(value.instances) == "function")
		and (value.definitions == nil or type(value.definitions) == "function")
end

---@class wiremux.validate.FieldSpec
---@field key string
---@field path string
---@field check fun(value: any): boolean
---@field message string

---Item fields, in check order. The first failure stops validation for that item.
---@type wiremux.validate.FieldSpec[]
local send_item_fields = {
	{
		key = "value",
		path = "item.value",
		check = function(value)
			return type(value) == "string"
		end,
		message = "wiremux.send item.value must be a string",
	},
	{
		key = "label",
		path = "item.label",
		check = optional_type("string"),
		message = "wiremux.send item.label must be a string",
	},
	{
		key = "title",
		path = "item.title",
		check = optional_type("string"),
		message = "wiremux.send item.title must be a string",
	},
	{
		key = "placeholders",
		path = "item.placeholders",
		check = optional_type("boolean"),
		message = "wiremux.send item.placeholders must be a boolean",
	},
}

---Resolved send option fields. Every failure is collected.
---@type wiremux.validate.FieldSpec[]
local send_option_fields = {
	{ key = "focus", path = "focus", check = optional_type("boolean"), message = "focus must be a boolean" },
	{
		key = "behavior",
		path = "behavior",
		check = member_of(valid.behaviors),
		message = "behavior must be one of: all, last, pick",
	},
	{
		key = "mode",
		path = "mode",
		check = member_of(valid.resolve_modes),
		message = "mode must be one of: all, auto, definitions, instances",
	},
	{ key = "target", path = "target", check = optional_type("string"), message = "target must be a string" },
	{ key = "filter", path = "filter", check = is_filter, message = "filter must contain function callbacks" },
	{ key = "submit", path = "submit", check = optional_type("boolean"), message = "submit must be a boolean" },
	{
		key = "pre_keys",
		path = "pre_keys",
		check = is_keys,
		message = "pre_keys must be a string or list of strings",
	},
	{
		key = "post_keys",
		path = "post_keys",
		check = is_keys,
		message = "post_keys must be a string or list of strings",
	},
}

---Option names an item may override, and therefore the only ones worth re-checking per item.
M.ITEM_OPTIONS = { submit = true, pre_keys = true, post_keys = true }

---Validate one send item.
---@param item any
---@return wiremux.Error[] errors
function M.send_item(item)
	if type(item) ~= "table" then
		return { validation_error("item", "wiremux.send item must be a table") }
	end
	for _, field in ipairs(send_item_fields) do
		if not field.check(item[field.key]) then
			return { validation_error(field.path, field.message) }
		end
	end
	return {}
end

---Validate resolved send options.
---@param options table
---@param only? table<string, true> Restrict the check to these option names.
---@return wiremux.Error[] errors
function M.send_options(options, only)
	local errors = {}
	for _, field in ipairs(send_option_fields) do
		if (only == nil or only[field.key]) and not field.check(options[field.key]) then
			table.insert(errors, validation_error(field.path, field.message))
		end
	end
	return errors
end

return M
