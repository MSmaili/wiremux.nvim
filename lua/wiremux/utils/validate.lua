local placeholder = require("wiremux.placeholder")

local M = {}

local valid = {
	behaviors = { last = true, pick = true, all = true },
	kinds = { pane = true, window = true },
	splits = { horizontal = true, vertical = true },
	split_modes = { before = true, after = true },
	log_levels = { off = true, error = true, warn = true, info = true, debug = true },
	compose_close_behaviors = { ask = true, hide = true, discard = true },
	compose_new_payload = { ask = true, keep = true, replace = true, append = true },
	compose_styles = { minimal = true },
	compose_borders = { none = true, single = true, double = true, rounded = true, solid = true, shadow = true },
	keymap_modes = { [""] = true, n = true, v = true, x = true, s = true, o = true, i = true, l = true, c = true, t = true, ["!"] = true },
	keymap_actions = { send = true, close = true, discard = true, files = true, delete_page = true, previous = true, next = true },
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

---@class wiremux.validate.Error
---@field path string
---@field message string

---@param path string
---@param message string
---@return wiremux.validate.Error
local function validation_error(path, message)
	return { path = path, message = message }
end

---@param value any
---@param valid_set table
---@return boolean
local function is_valid(value, valid_set)
	return value == nil or valid_set[value] ~= nil
end

---@class ValidateFieldOpts
---@field valid_set table
---@field name string
---@field context? string

---@param value any
---@param opts ValidateFieldOpts
---@return string? error
local function validate_field(value, opts)
	if is_valid(value, opts.valid_set) then
		return nil
	end

	local valid_values = table.concat(vim.fn.sort(vim.tbl_keys(opts.valid_set)), ", ")
	return string.format(
		"invalid %s '%s'%s, use: %s",
		opts.name,
		tostring(value),
		opts.context and " " .. opts.context or "",
		valid_values
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
				string.format("context resolver name '%s' must match %s", tostring(name), placeholder.validation_pattern)
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
---@return wiremux.validate.Error[]
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
	if keymap.desc ~= nil and type(keymap.desc) ~= "string" then
		table.insert(errors, validation_error(path .. ".desc", path .. ".desc must be a string"))
	end
	return errors
end

---@param entry any
---@param path string
---@return wiremux.validate.Error[]
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
---@return wiremux.validate.Error[]
local function validate_keymaps(keymaps, path)
	if type(keymaps) ~= "table" then
		return { validation_error(path, string.format("%s must be a table, got %s", path, type(keymaps))) }
	end

	local errors = {}
	for action, entry in pairs(keymaps) do
		if not valid.keymap_actions[action] then
			table.insert(errors, validation_error(path .. "." .. tostring(action), string.format(
				"unknown compose keymap action '%s' for %s",
				tostring(action),
				path
			)))
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

---Validate and copy a placeholder capture-name list.
---@param capture_names any
---@param path string
---@param known_placeholders? table<string, true>
---@return string[]? normalized
---@return wiremux.validate.Error[] errors
function M.capture_names(capture_names, path, known_placeholders)
	if type(capture_names) ~= "table" or not vim.islist(capture_names) then
		return nil, {
			validation_error(path, string.format("%s must be a list of placeholder names", path)),
		}
	end

	local normalized = {}
	local errors = {}
	local seen = {}
	for index, name in ipairs(capture_names) do
		local item_path = string.format("%s[%d]", path, index)
		if not placeholder.is_valid_name(name) then
			table.insert(errors, validation_error(
				item_path,
				string.format("%s must be a placeholder name matching %s", item_path, placeholder.validation_pattern)
			))
		elseif known_placeholders and not known_placeholders[name] then
			table.insert(errors, validation_error(item_path, string.format("unknown placeholder '%s' in %s", name, path)))
		elseif not seen[name] then
			seen[name] = true
			table.insert(normalized, name)
		end
	end
	return normalized, errors
end

---@class wiremux.validate.ComposeOptionsOptions
---@field path? string
---@field allow_capture_placeholders? boolean
---@field known_placeholders? table<string, true>

---Validate and copy a partial compose option table.
---@param options any
---@param opts? wiremux.validate.ComposeOptionsOptions
---@return table normalized
---@return wiremux.validate.Error[] errors
function M.compose_options(options, opts)
	opts = opts or {}
	local path = opts.path or "compose"
	if type(options) ~= "table" then
		return {}, {
			validation_error(path, string.format("%s must be a boolean or table, got %s", path, type(options))),
		}
	end

	local normalized = {}
	local errors = {}
	for field, value in pairs(options) do
		local field_path = path .. "." .. tostring(field)
		if field == "capture_placeholders" then
			if not opts.allow_capture_placeholders then
				table.insert(errors, validation_error(
					field_path,
					"capture_placeholders is only allowed at ui.compose.capture_placeholders"
				))
			else
				local names, name_errors = M.capture_names(value, field_path, opts.known_placeholders)
				vim.list_extend(errors, name_errors)
				if names ~= nil then
					normalized.capture_placeholders = names
				end
			end
		elseif not compose_session_fields[field] then
			table.insert(errors, validation_error(field_path, string.format("unknown compose option '%s' for %s", tostring(field), path)))
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
				table.insert(errors, validation_error(field_path, field_path .. " must be a valid border name or segment list"))
			end
		elseif field == "style" then
			local message = validate_field(value, {
				valid_set = valid.compose_styles,
				name = "style",
				context = "for " .. path,
			})
			if message then
				table.insert(errors, validation_error(field_path, message))
			else
				normalized.style = value
			end
		elseif field == "close_behavior" then
			local message = validate_field(value, {
				valid_set = valid.compose_close_behaviors,
				name = "close_behavior",
				context = "for " .. path,
			})
			if message then
				table.insert(errors, validation_error(field_path, message))
			else
				normalized.close_behavior = value
			end
		elseif field == "on_new_payload" then
			local message = validate_field(value, {
				valid_set = valid.compose_new_payload,
				name = "on_new_payload",
				context = "for " .. path,
			})
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
	if overrides.capture_placeholders ~= nil then
		merged.capture_placeholders = vim.deepcopy(overrides.capture_placeholders)
	end
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
---@param defaults wiremux.config.ComposeUIConfig
---@param known_placeholders table<string, true>
---@return wiremux.config.ComposeUIConfig normalized
---@return wiremux.validate.Error[] errors
function M.normalize_global_compose(options, defaults, known_placeholders)
	if options == nil then
		return vim.deepcopy(defaults), {}
	end
	if type(options) ~= "table" then
		return vim.deepcopy(defaults), {
			validation_error("ui.compose", string.format("ui.compose must be a table, got %s", type(options))),
		}
	end

	local normalized, errors = M.compose_options(options, {
		path = "ui.compose",
		allow_capture_placeholders = true,
		known_placeholders = known_placeholders,
	})
	return merge_compose(defaults, normalized), errors
end

---Normalize the global actions.send.compose default.
---@param value any
---@param default boolean|table
---@return boolean|table normalized
---@return wiremux.validate.Error[] errors
function M.normalize_action_compose(value, default)
	if value == nil then
		return vim.deepcopy(default), {}
	end
	if type(value) == "boolean" then
		return value, {}
	end
	if type(value) ~= "table" then
		return vim.deepcopy(default), {
			validation_error(
				"actions.send.compose",
				string.format("actions.send.compose must be a boolean or table, got %s", type(value))
			),
		}
	end

	local normalized, errors = M.compose_options(value, { path = "actions.send.compose" })
	return normalized, errors
end

---Resolve one selected runtime compose value into a complete session-only config.
---@param global_compose wiremux.config.ComposeUIConfig
---@param value any
---@param path string
---@return wiremux.config.ComposeSessionConfig? config
---@return wiremux.validate.Error[] errors
function M.resolve_compose(global_compose, value, path)
	if value == nil or value == false then
		return nil, {}
	end
	if value == true then
		value = {}
	elseif type(value) ~= "table" then
		return nil, {
			validation_error(path, string.format("%s must be a boolean or table, got %s", path, type(value))),
		}
	end

	local overrides, errors = M.compose_options(value, { path = path })
	if #errors > 0 then
		return nil, errors
	end
	local session_defaults = vim.deepcopy(global_compose)
	session_defaults.capture_placeholders = nil
	return merge_compose(session_defaults, overrides), {}
end

---@param errors wiremux.validate.Error[]
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

	collect_error(validate_field(opts.log_level, {
		valid_set = valid.log_levels,
		name = "log_level",
	}))

	for name, def in pairs(vim.tbl_get(opts, "targets", "definitions") or {}) do
		collect_error(validate_kind(def.kind, name))
		collect_error(validate_field(def.split, {
			valid_set = valid.splits,
			name = "split",
			context = "for target '" .. name .. "'",
		}))
		collect_error(validate_field(def.split_mode, {
			valid_set = valid.split_modes,
			name = "split_mode",
			context = "for target '" .. name .. "'",
		}))
	end

	for action, cfg in pairs(opts.actions or {}) do
		collect_error(validate_field(cfg.behavior, {
			valid_set = valid.behaviors,
			name = "behavior",
			context = "for action '" .. action .. "'",
		}))
	end

	collect_error(validate_picker(opts.picker))
	vim.list_extend(errors, validate_resolvers(vim.tbl_get(opts, "context", "resolvers")))
	return errors
end

return M
