local M = {}
---@alias wiremux.ResolveMode "instances"|"definitions"

---@class wiremux.ResolveOpts
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode
---@field filter? wiremux.config.FilterConfig

---@class wiremux.ResolveResult.Targets
---@field kind "targets"
---@field targets wiremux.Instance[]

---@class wiremux.ResolveItem.Instance
---@field type "instance"
---@field instance wiremux.Instance
---@field target string
---@field label string

---@class wiremux.ResolveItem.Definition
---@field type "definition"
---@field target string
---@field def wiremux.target.definition
---@field label string

---@alias wiremux.ResolveItem wiremux.ResolveItem.Instance | wiremux.ResolveItem.Definition

---@class wiremux.ResolveResult.Pick
---@field kind "pick"
---@field items wiremux.ResolveItem[]

---@alias wiremux.ResolveResult wiremux.ResolveResult.Targets | wiremux.ResolveResult.Pick

---@param instances wiremux.Instance[]
---@param filter_fn? fun(inst: wiremux.Instance, state: wiremux.State): boolean
---@param state wiremux.State
---@return wiremux.Instance[]
local function filter_instances(instances, filter_fn, state)
	if not filter_fn then
		return instances
	end

	return vim.iter(instances)
		:filter(function(inst)
			return filter_fn(inst, state)
		end)
		:totable()
end

---@param definitions table<string, wiremux.target.definition>
---@param filter_fn? fun(def: wiremux.target.definition, name: string, state: wiremux.State): boolean
---@param state wiremux.State
---@return table<string, wiremux.target.definition>
local function filter_definitions(definitions, filter_fn, state)
	if not filter_fn then
		return definitions
	end

	local filtered = {}
	for name, def in pairs(definitions) do
		if filter_fn(def, name, state) then
			filtered[name] = def
		end
	end
	return filtered
end

---@param instances wiremux.Instance[]
---@return wiremux.ResolveItem.Instance[]
local function build_instance_items(instances)
	local counts = {}

	local items = vim.iter(instances)
		:map(function(inst)
			local target = inst.target
			counts[target] = (counts[target] or 0) + 1
			return {
				type = "instance",
				instance = inst,
				target = target,
				label = target .. " #" .. counts[target],
			}
		end)
		:totable()

	table.sort(items, function(a, b)
		return a.target < b.target
	end)

	return items
end

---@param definitions table<string, wiremux.target.definition>
---@return wiremux.ResolveItem.Definition[]
local function build_definition_items(definitions)
	local items = vim.iter(definitions or {})
		:map(function(name, def)
			return {
				type = "definition",
				target = name,
				def = def,
				label = "[+] " .. name,
			}
		end)
		:totable()

	table.sort(items, function(a, b)
		return a.target < b.target
	end)

	return items
end

---@param state wiremux.State
---@param definitions table<string, wiremux.target.definition>
---@param opts wiremux.ResolveOpts
---@return wiremux.ResolveResult
function M.resolve(state, definitions, opts)
	local config = require("wiremux.config")

	-- Merge filters: action-specific overrides global
	local action_filter = opts.filter or {}
	local global_filter = config.opts.filter or {}

	local instance_filter = action_filter.instances or global_filter.instances
	local definition_filter = action_filter.definitions or global_filter.definitions

	-- Apply filters
	local instances = filter_instances(state.instances, instance_filter, state)
	local filtered_defs = filter_definitions(definitions, definition_filter, state)

	local last_used = state.last_used_target_id

	-- Definitions mode - only show definitions
	if opts.mode == "definitions" then
		return { kind = "pick", items = build_definition_items(filtered_defs) }
	end

	-- No instances - fallback to definitions
	if #instances == 0 then
		return { kind = "pick", items = build_definition_items(filtered_defs) }
	end

	-- Behavior: all
	if opts.behavior == "all" then
		return { kind = "targets", targets = instances }
	end

	-- Single instance - use it directly
	if #instances == 1 then
		return { kind = "targets", targets = { instances[1] } }
	end

	-- Behavior: pick
	if opts.behavior == "pick" then
		return { kind = "pick", items = build_instance_items(instances) }
	end

	-- Behavior: last
	if last_used then
		for _, inst in ipairs(instances) do
			if inst.id == last_used then
				return { kind = "targets", targets = { inst } }
			end
		end
	end

	-- Fallback to picker
	return { kind = "pick", items = build_instance_items(instances) }
end

return M
