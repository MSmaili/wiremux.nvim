local M = {}

---@alias wiremux.ResolveMode "instances"|"definitions"|"both"

---@class wiremux.ResolveOpts
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode
---@field filter? wiremux.config.FilterConfig

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

---@class wiremux.ResolveResult.Targets
---@field kind "targets"
---@field targets wiremux.Instance[]

---@class wiremux.ResolveResult.Pick
---@field kind "pick"
---@field items wiremux.ResolveItem[]

---@alias wiremux.ResolveResult wiremux.ResolveResult.Targets | wiremux.ResolveResult.Pick

---Filter instances based on filter function
---@param instances wiremux.Instance[]
---@param filter_fn? fun(inst: wiremux.Instance, state: wiremux.State): boolean
---@param state wiremux.State
---@return wiremux.Instance[]
function M.filter_instances(instances, filter_fn, state)
	return vim.iter(instances)
		:filter(function(inst)
			if inst.id == state.origin_pane_id then
				return false
			end
			if filter_fn then
				return filter_fn(inst, state)
			end
			return true
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
	return vim.iter(instances)
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
end

---@param definitions table<string, wiremux.target.definition>
---@return wiremux.ResolveItem.Definition[]
local function build_definition_items(definitions)
	return vim.iter(definitions or {})
		:map(function(name, def)
			return {
				type = "definition",
				target = name,
				def = def,
				label = "[+] " .. name,
			}
		end)
		:totable()
end

---@param items wiremux.ResolveItem[]
---@return wiremux.ResolveResult.Pick
local function pick_result(items)
	return { kind = "pick", items = items }
end

---@param targets wiremux.Instance[]
---@return wiremux.ResolveResult.Targets
local function targets_result(targets)
	return { kind = "targets", targets = targets }
end

---@param instances wiremux.Instance[]
---@param behavior wiremux.action.Behavior
---@param last_used string?
---@return wiremux.ResolveResult
local function resolve_by_behavior(instances, behavior, last_used)
	if behavior == "all" then
		return targets_result(instances)
	end

	if #instances == 1 then
		return targets_result({ instances[1] })
	end

	if behavior == "pick" then
		return pick_result(build_instance_items(instances))
	end

	if behavior == "last" and last_used then
		for _, inst in ipairs(instances) do
			if inst.id == last_used then
				return targets_result({ inst })
			end
		end
	end

	return pick_result(build_instance_items(instances))
end

---@param state wiremux.State
---@param definitions table<string, wiremux.target.definition>
---@param opts wiremux.ResolveOpts
---@return wiremux.ResolveResult
function M.resolve(state, definitions, opts)
	local config = require("wiremux.config")
	local action_filter = opts.filter or {}
	local global_filter = config.opts.filter or {}
	local last_used = state.last_used_target_id

	local instances = M.filter_instances(state.instances, action_filter.instances or global_filter.instances, state)
	local filtered_defs = filter_definitions(definitions, action_filter.definitions or global_filter.definitions, state)

	if opts.mode == "definitions" then
		return pick_result(build_definition_items(filtered_defs))
	end

	if opts.mode == "instances" then
		if #instances == 0 then
			return pick_result({})
		end
		return resolve_by_behavior(instances, opts.behavior, last_used)
	end

	if #instances == 0 then
		return pick_result(build_definition_items(filtered_defs))
	end

	return resolve_by_behavior(instances, opts.behavior, last_used)
end

return M
