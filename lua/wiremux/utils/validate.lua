local placeholder = require("wiremux.placeholder")

local M = {}

local valid = {
	behaviors = { last = true, pick = true, all = true },
	resolve_modes = { auto = true, instances = true, definitions = true, all = true },
	kinds = { pane = true, window = true },
	splits = { horizontal = true, vertical = true },
	split_modes = { before = true, after = true },
	log_levels = { off = true, error = true, warn = true, info = true, debug = true },
}

---@class wiremux.Error
---@field path string
---@field message string

---@param path string
---@param message string
---@return wiremux.Error
function M.error(path, message)
	return { path = path, message = message }
end

local validation_error = M.error

---@param valid_set table<string, true>
---@return string[]
local function sorted_keys(valid_set)
	local keys = vim.tbl_keys(valid_set)
	table.sort(keys)
	return keys
end

---Check set membership, treating nil as valid, and format the shared "use: ..." message.
---@param value any
---@param valid_set table<string, true>
---@param name string
---@param context? string
---@return string? error
function M.enum(value, valid_set, name, context)
	if value == nil or valid_set[value] ~= nil then
		return nil
	end

	return string.format(
		"invalid %s '%s'%s, use: %s",
		name,
		tostring(value),
		context and " " .. context or "",
		table.concat(sorted_keys(valid_set), ", ")
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
---@return wiremux.Error[] errors
local function validate_resolvers(resolvers)
	local errors = {}

	if resolvers == nil then
		return errors
	end
	if type(resolvers) ~= "table" then
		return {
			validation_error(
				"context.resolvers",
				string.format("context.resolvers must be table, got %s", type(resolvers))
			),
		}
	end

	for name, resolver in pairs(resolvers) do
		local path = "context.resolvers." .. tostring(name)
		if not placeholder.is_valid_name(name) then
			table.insert(
				errors,
				validation_error(
					path,
					string.format(
						"context resolver name '%s' must match %s",
						tostring(name),
						placeholder.validation_pattern
					)
				)
			)
		elseif type(resolver) ~= "function" then
			table.insert(
				errors,
				validation_error(
					path,
					string.format("context resolver '%s' is not a function (got %s)", name, type(resolver))
				)
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

---@param errors wiremux.Error[]
---@return string[]
function M.error_messages(errors)
	local messages = {}
	for _, err in ipairs(errors) do
		table.insert(messages, err.message)
	end
	return messages
end

---Check the user configuration. Every check collects, so one call reports every problem.
---@param opts table
---@return wiremux.Error[] errors
function M.validate(opts)
	local errors = {}
	---@param path string
	---@param message string?
	local function collect(path, message)
		if message then
			table.insert(errors, validation_error(path, message))
		end
	end

	collect("log_level", M.enum(opts.log_level, valid.log_levels, "log_level"))

	for name, def in pairs(vim.tbl_get(opts, "targets", "definitions") or {}) do
		local path = "targets.definitions." .. tostring(name)
		local context = "for target '" .. name .. "'"
		collect(path .. ".kind", validate_kind(def.kind, name))
		collect(path .. ".split", M.enum(def.split, valid.splits, "split", context))
		collect(path .. ".split_mode", M.enum(def.split_mode, valid.split_modes, "split_mode", context))
	end

	for action, cfg in pairs(opts.actions or {}) do
		local context = "for action '" .. action .. "'"
		collect(
			"actions." .. tostring(action) .. ".behavior",
			M.enum(cfg.behavior, valid.behaviors, "behavior", context)
		)
	end

	collect("picker", validate_picker(opts.picker))
	vim.list_extend(errors, validate_resolvers(vim.tbl_get(opts, "context", "resolvers")))
	return errors
end

---Accepted value sets. Read-only.
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
---@field path? string Error path, when it differs from the key.
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

---Resolved send option fields, and the single registry of send option names. Every failure is
---collected. The option path and the option key are the same, so these entries omit path.
---@type wiremux.validate.FieldSpec[]
local send_option_fields = {
	{ key = "focus", check = optional_type("boolean"), message = "focus must be a boolean" },
	{ key = "behavior", check = member_of(valid.behaviors), message = "behavior must be one of: all, last, pick" },
	{
		key = "mode",
		check = member_of(valid.resolve_modes),
		message = "mode must be one of: all, auto, definitions, instances",
	},
	{ key = "target", check = optional_type("string"), message = "target must be a string" },
	{ key = "filter", check = is_filter, message = "filter must contain function callbacks" },
	{ key = "submit", check = optional_type("boolean"), message = "submit must be a boolean" },
	{ key = "pre_keys", check = is_keys, message = "pre_keys must be a string or list of strings" },
	{ key = "post_keys", check = is_keys, message = "post_keys must be a string or list of strings" },
}

---Option names that an item can override.
local item_option_keys = { submit = true, pre_keys = true, post_keys = true }

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

---Check the resolved send options for a call.
---@param options table
---@param only? table<string, true> Restrict the check to these option names.
---@return wiremux.Error[] errors
function M.send_options(options, only)
	local errors = {}
	for _, field in ipairs(send_option_fields) do
		if (only == nil or only[field.key]) and not field.check(options[field.key]) then
			table.insert(errors, validation_error(field.path or field.key, field.message))
		end
	end
	return errors
end

---Check the send options that one item overrides.
---@param overrides table
---@return wiremux.Error[] errors
function M.send_item_options(overrides)
	return M.send_options(overrides, item_option_keys)
end

return M
