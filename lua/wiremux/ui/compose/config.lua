-- Assembly of compose session configuration: check a partial option table, normalize it, and merge
-- it with the global compose config. `wiremux.utils.validate` supplies the checks; this module owns
-- the compose option shape.

local validate = require("wiremux.utils.validate")

local M = {}

local valid = {
	styles = { minimal = true },
	close_behaviors = { ask = true, hide = true, discard = true },
	new_payload = { ask = true, keep = true, replace = true, append = true },
	borders = { none = true, single = true, double = true, rounded = true, solid = true, shadow = true },
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
		return { validate.error(path, string.format("%s must be a keymap table, got %s", path, type(keymap))) }
	end
	if type(keymap[1]) ~= "string" or keymap[1] == "" then
		table.insert(errors, validate.error(path .. "[1]", path .. "[1] must be a non-empty key string"))
	end
	if keymap.mode ~= nil and not valid_keymap_mode(keymap.mode) then
		table.insert(errors, validate.error(path .. ".mode", path .. ".mode contains an invalid mapping mode"))
	end
	return errors
end

---@param entry any
---@param path string
---@return wiremux.Error[]
local function validate_keymap_entry(entry, path)
	if type(entry) ~= "table" then
		return { validate.error(path, string.format("%s must be a keymap table or list, got %s", path, type(entry))) }
	end
	if next(entry) == nil then
		return {}
	end
	if type(entry[1]) == "string" then
		return validate_keymap(entry, path)
	end
	if not vim.islist(entry) then
		return { validate.error(path, path .. " must be a keymap table or list") }
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
		return { validate.error(path, string.format("%s must be a table, got %s", path, type(keymaps))) }
	end

	local errors = {}
	for action, entry in pairs(keymaps) do
		if not valid.keymap_actions[action] then
			table.insert(
				errors,
				validate.error(
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
		return valid.borders[border] == true
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

local session_fields = {
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

---Check and copy a partial compose option table.
---@param options any
---@param path? string
---@return table normalized
---@return wiremux.Error[] errors
function M.options(options, path)
	path = path or "compose"
	if type(options) ~= "table" then
		return {}, {
			validate.error(path, string.format("%s must be a boolean or table, got %s", path, type(options))),
		}
	end

	local normalized = {}
	local errors = {}
	for field, value in pairs(options) do
		local field_path = path .. "." .. tostring(field)
		if not session_fields[field] then
			table.insert(
				errors,
				validate.error(field_path, string.format("unknown compose option '%s' for %s", tostring(field), path))
			)
		elseif field == "width" or field == "height" then
			if type(value) == "number" and value >= 0.1 and value <= 1 then
				normalized[field] = value
			else
				table.insert(errors, validate.error(field_path, field_path .. " must be a number between 0.1 and 1"))
			end
		elseif field == "title" then
			if type(value) == "string" then
				normalized.title = value
			else
				table.insert(errors, validate.error(field_path, field_path .. " must be a string"))
			end
		elseif field == "border" then
			if valid_border(value) then
				normalized.border = vim.deepcopy(value)
			else
				table.insert(
					errors,
					validate.error(field_path, field_path .. " must be a valid border name or segment list")
				)
			end
		elseif field == "style" then
			local message = validate.enum(value, valid.styles, "style", "for " .. path)
			if message then
				table.insert(errors, validate.error(field_path, message))
			else
				normalized.style = value
			end
		elseif field == "close_behavior" then
			local message = validate.enum(value, valid.close_behaviors, "close_behavior", "for " .. path)
			if message then
				table.insert(errors, validate.error(field_path, message))
			else
				normalized.close_behavior = value
			end
		elseif field == "on_new_payload" then
			local message = validate.enum(value, valid.new_payload, "on_new_payload", "for " .. path)
			if message then
				table.insert(errors, validate.error(field_path, message))
			else
				normalized.on_new_payload = value
			end
		elseif field == "wo" then
			if type(value) == "table" then
				normalized.wo = vim.deepcopy(value)
			else
				table.insert(errors, validate.error(field_path, field_path .. " must be a table"))
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
local function merge(base, overrides)
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
function M.normalize_global(options, defaults)
	if options == nil then
		return vim.deepcopy(defaults), {}
	end
	if type(options) ~= "table" then
		return vim.deepcopy(defaults),
			{
				validate.error("ui.compose", string.format("ui.compose must be a table, got %s", type(options))),
			}
	end

	local normalized, errors = M.options(options, "ui.compose")
	return merge(defaults, normalized), errors
end

---Normalize the global actions.send.compose default.
---@param value any
---@param default boolean|table
---@return boolean|table normalized
---@return wiremux.Error[] errors
function M.normalize_action(value, default)
	if value == nil then
		return vim.deepcopy(default), {}
	end
	if type(value) == "boolean" then
		return value, {}
	end
	if type(value) ~= "table" then
		return vim.deepcopy(default),
			{
				validate.error(
					"actions.send.compose",
					string.format("actions.send.compose must be a boolean or table, got %s", type(value))
				),
			}
	end

	return M.options(value, "actions.send.compose")
end

---Resolve one selected runtime compose value into a complete session-only config.
---@param global_compose wiremux.config.ComposeSessionConfig
---@param value any
---@param path string
---@return wiremux.config.ComposeSessionConfig? config
---@return wiremux.Error[] errors
function M.resolve(global_compose, value, path)
	if value == nil or value == false then
		return nil, {}
	end
	if value == true then
		value = {}
	elseif type(value) ~= "table" then
		return nil,
			{
				validate.error(path, string.format("%s must be a boolean or table, got %s", path, type(value))),
			}
	end

	local overrides, errors = M.options(value, path)
	if #errors > 0 then
		return nil, errors
	end
	return merge(global_compose, overrides), {}
end

return M
