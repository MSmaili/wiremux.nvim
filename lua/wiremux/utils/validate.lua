local M = {}

local valid = {
	behaviors = { last = true, pick = true, all = true },
	kinds = { pane = true, window = true },
	splits = { horizontal = true, vertical = true },
	log_levels = { off = true, error = true, warn = true, info = true, debug = true },
}

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
		if type(resolver) ~= "function" then
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
		for _, v in ipairs(kind) do
			if type(v) ~= "string" or not valid.kinds[v] then
				return string.format(
					"invalid kind value '%s' in table for target '%s', use: pane, window",
					tostring(v),
					target_name
				)
			end
			if seen[v] then
				return string.format("duplicate kind '%s' in table for target '%s'", v, target_name)
			end
			seen[v] = true
		end
		return nil
	end

	return string.format("kind for target '%s' must be string or table, got %s", target_name, type(kind))
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
