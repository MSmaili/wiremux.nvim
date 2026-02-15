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

---Get filter function from action-level override or global picker config.
---@param action_filter? wiremux.config.FilterConfig
---@param action_key string Key in action_filter (e.g. "instances", "definitions")
---@param config_path string[] Path into config.opts.picker (e.g. {"instances", "filter"})
---@return function?
local function get_filter_fn(action_filter, action_key, config_path)
	if action_filter and action_filter[action_key] then
		return action_filter[action_key]
	end
	local config = require("wiremux.config")
	local node = config.opts.picker
	for _, key in ipairs(config_path) do
		if not node then
			return nil
		end
		node = node[key]
	end
	return type(node) == "function" and node or nil
end

---Filter instances based on filter function
---@param instances wiremux.Instance[]
---@param state wiremux.State
---@param action_filter? wiremux.config.FilterConfig
---@return wiremux.Instance[]
function M.filter_instances(instances, state, action_filter)
	local filter_fn = get_filter_fn(action_filter, "instances", { "instances", "filter" })

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

---Sort instances
---@param instances wiremux.Instance[]
---@return wiremux.Instance[]
local function sort_instances(instances)
	local sort_fn = get_filter_fn(nil, "", { "instances", "sort" })

	if not sort_fn then
		return instances
	end

	local sorted = vim.list_slice(instances)
	table.sort(sorted, sort_fn)
	return sorted
end

---Filter definitions
---@param definitions table<string, wiremux.target.definition>
---@param action_filter? wiremux.config.FilterConfig
---@return table<string, wiremux.target.definition>
local function filter_definitions(definitions, action_filter)
	local filter_fn = get_filter_fn(action_filter, "definitions", { "targets", "filter" })

	if not filter_fn then
		return definitions
	end

	local filtered = {}
	for name, def in pairs(definitions) do
		if filter_fn(name, def) then
			filtered[name] = def
		end
	end
	return filtered
end

---Get display name for instance
---@param inst wiremux.Instance
---@param def wiremux.target.definition?
---@param index number
---@return string
local function get_display_name(inst, def, index)
	if def and type(def.label) == "function" then
		local ok, result = pcall(def.label, inst, index)
		if ok and type(result) == "string" then
			return result
		elseif not ok then
			require("wiremux.utils.notify").debug("Label function error for %s: %s", inst.target, result)
		end
	end

	local name
	if inst.kind == "window" and inst.window_name and inst.window_name ~= "" then
		name = inst.window_name
	elseif def and type(def.label) == "string" then
		name = def.label
	else
		name = inst.target
	end

	local label = string.format("%s #%d", name, index)

	if inst.running_command and inst.running_command ~= "" then
		label = label .. string.format(" [%s]", inst.running_command)
	end

	return label
end

---@param instances wiremux.Instance[]
---@return wiremux.ResolveItem.Instance[]
local function build_instance_items(instances)
	local config = require("wiremux.config")
	local definitions = (config.opts.targets and config.opts.targets.definitions) or {}

	local counts = vim.defaulttable(function()
		return 0
	end)
	return vim.iter(instances)
		:map(function(inst)
			local target = inst.target
			counts[target] = counts[target] + 1

			local def = definitions[target]
			local label = get_display_name(inst, def, counts[target])

			return {
				type = "instance",
				instance = inst,
				target = target,
				label = label,
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
---@param instances wiremux.Instance[]
---@return wiremux.ResolveResult.Pick
local function pick_from_instances(instances)
	local sorted = sort_instances(instances)
	return pick_result(build_instance_items(sorted))
end

local function resolve_by_behavior(instances, behavior, last_used)
	if behavior == "all" then
		return targets_result(instances)
	end

	if #instances == 1 then
		return targets_result({ instances[1] })
	end

	if behavior == "last" and last_used then
		for _, inst in ipairs(instances) do
			if inst.id == last_used then
				return targets_result({ inst })
			end
		end
	end

	return pick_from_instances(instances)
end

---@param state wiremux.State
---@param definitions table<string, wiremux.target.definition>
---@param opts wiremux.ResolveOpts
---@return wiremux.ResolveResult
function M.resolve(state, definitions, opts)
	local last_used = state.last_used_target_id

	local instances = M.filter_instances(state.instances, state, opts.filter)
	local filtered_defs = filter_definitions(definitions, opts.filter)

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

	if opts.filter and opts.filter.definitions then
		local result = pick_from_instances(instances)
		vim.list_extend(result.items, build_definition_items(filtered_defs))
		return result
	end

	return resolve_by_behavior(instances, opts.behavior, last_used)
end

return M
