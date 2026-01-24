local M = {}

local valid = {
	behaviors = { last = true, pick = true, all = true },
	kinds = { pane = true, window = true },
	splits = { horizontal = true, vertical = true },
	log_levels = { off = true, error = true, warn = true, info = true, debug = true },
}

local function is_valid(value, valid_set)
	return not value or valid_set[value] ~= nil
end

local function validate_field(value, valid_set, field_name, context, default)
	if not is_valid(value, valid_set) then
		local valid_values = table.concat(vim.tbl_keys(valid_set), ", ")
		require("wiremux.utils.notify").warn(
			string.format("invalid %s '%s' %s, use: %s", field_name, value, context, valid_values)
		)
		return default
	end
	return value
end

function M.validate(opts)
	opts.log_level = validate_field(opts.log_level, valid.log_levels, "log_level", "", "warn")

	for name, def in pairs(opts.targets.definitions) do
		def.kind = validate_field(def.kind, valid.kinds, "kind", "for target '" .. name .. "'", "pane")
		def.split = validate_field(def.split, valid.splits, "split", "for target '" .. name .. "'", "vertical")
	end

	for action, cfg in pairs(opts.actions) do
		cfg.behavior =
			validate_field(cfg.behavior, valid.behaviors, "behavior", "for action '" .. action .. "'", "last")
	end
end

return M
