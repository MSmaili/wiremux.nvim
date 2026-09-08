local M = {}
local instance = require("wiremux.core.instance")

---@alias wiremux.ResolveMode "instances"|"definitions"|"all"|"auto"

---@class wiremux.ResolveOpts
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode
---@field filter? wiremux.config.FilterConfig
---@field target? string Target definition name for explicit targeting
---@field allow_adopt? boolean Internal action capability; unmanaged instances are never queried without it.

---@class wiremux.ResolveItem.Instance
---@field type "instance"
---@field instance wiremux.ManagedInstance
---@field target string
---@field label string

---@class wiremux.ResolveItem.Adopt
---@field type "adopt"
---@field instance wiremux.Instance
---@field label string

---@class wiremux.ResolveItem.Definition
---@field type "definition"
---@field target string
---@field def wiremux.target.definition
---@field label string

---@alias wiremux.ResolveItem wiremux.ResolveItem.Instance | wiremux.ResolveItem.Adopt | wiremux.ResolveItem.Definition

---@class wiremux.ResolveResult.Targets
---@field kind "targets"
---@field targets wiremux.ManagedInstance[]

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
---@generic T: wiremux.Instance
---@param instances T[]
---@param state wiremux.State
---@param action_filter? wiremux.config.FilterConfig
---@return T[]
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
---@param instances wiremux.ManagedInstance[]
---@return wiremux.ManagedInstance[]
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
---@param inst wiremux.ManagedInstance
---@param def wiremux.target.definition?
---@param index number
---@param state wiremux.State
---@return string
local function get_display_name(inst, def, index, state)
	if not def and inst.target == instance.default_target_name(inst) then
		return string.format("[m] %-6s %s", instance.location(inst, state), inst.running_command or "adopted")
	end

	local configured_label = def and def.label or nil
	if type(configured_label) == "function" then
		local ok, result = pcall(configured_label, inst, index)
		if ok and type(result) == "string" then
			return result
		elseif not ok then
			require("wiremux.utils.notify").debug("Label function error for %s: %s", inst.target, result)
		end
	end

	local name
	if inst.kind == "window" and inst.window_name and inst.window_name ~= "" then
		name = inst.window_name
	elseif type(configured_label) == "string" then
		name = configured_label
	else
		name = inst.target
	end

	local label = string.format("[m] %-6s %s", instance.location(inst, state), name)
	if inst.running_command and inst.running_command ~= "" then
		label = label .. string.format(" [%s]", inst.running_command)
	end
	return label
end

---@param instances wiremux.ManagedInstance[]
---@param state wiremux.State
---@return wiremux.ResolveItem.Instance[]
local function build_instance_items(instances, state)
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
			local label = get_display_name(inst, def, counts[target], state)

			return {
				type = "instance",
				instance = inst,
				target = target,
				label = label,
			}
		end)
		:totable()
end

---@param inst wiremux.Instance
---@param state wiremux.State
---@return string
local function get_adopt_display_name(inst, state)
	local label = string.format("[~] %-6s", instance.location(inst, state))
	if inst.running_command and inst.running_command ~= "" then
		label = label .. " " .. inst.running_command
	end
	return label
end

---@param instances wiremux.Instance[]
---@param state wiremux.State
---@return wiremux.ResolveItem.Adopt[]
local function build_adopt_items(instances, state)
	return vim.iter(instances)
		:map(function(inst)
			return {
				type = "adopt",
				instance = inst,
				label = get_adopt_display_name(inst, state),
			}
		end)
		:totable()
end

---@param state wiremux.State
---@param action_filter? wiremux.config.FilterConfig
---@return wiremux.Instance[]
local function get_unmanaged_instances(state, action_filter)
	local unmanaged = vim.iter(state.panes or {})
		:filter(function(inst)
			return not inst.managed
		end)
		:totable()
	return M.filter_instances(unmanaged, state, action_filter)
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

---@param targets wiremux.ManagedInstance[]
---@return wiremux.ResolveResult.Targets
local function targets_result(targets)
	return { kind = "targets", targets = targets }
end

---@param instances wiremux.ManagedInstance[]
---@param behavior wiremux.action.Behavior
---@param state wiremux.State
---@return wiremux.ResolveResult
local function resolve_by_behavior(instances, behavior, state)
	if behavior == "all" then
		return targets_result(instances)
	end

	if #instances == 1 then
		return targets_result({ instances[1] })
	end

	if behavior == "last" and state.last_used_target_id then
		for _, inst in ipairs(instances) do
			if inst.id == state.last_used_target_id then
				return targets_result({ inst })
			end
		end
	end

	return pick_result(build_instance_items(sort_instances(instances), state))
end

---Resolve when an explicit target name is provided.
---Filters instances by target name (on top of normal filters), auto-creates if none found.
---@param state wiremux.State
---@param instances wiremux.ManagedInstance[]
---@param definitions table<string, wiremux.target.definition>
---@param opts wiremux.ResolveOpts
---@return wiremux.ResolveResult
local function resolve_explicit_target(state, instances, definitions, opts)
	local target_instances = vim.iter(instances)
		:filter(function(inst)
			return inst.target == opts.target
		end)
		:totable()

	if #target_instances > 0 then
		return resolve_by_behavior(target_instances, opts.behavior, state)
	end

	local def = definitions[opts.target]
	if def then
		return pick_result(build_definition_items({ [opts.target] = def }))
	end

	require("wiremux.utils.notify").warn(string.format("Target '%s' not found in definitions", opts.target))
	return pick_result({})
end

---@param state wiremux.State
---@param definitions table<string, wiremux.target.definition>
---@param opts wiremux.ResolveOpts
---@return wiremux.ResolveResult
function M.resolve(state, definitions, opts)
	local instances = M.filter_instances(state.instances or {}, state, opts.filter)
	local filtered_defs = filter_definitions(definitions, opts.filter)

	if opts.target then
		return resolve_explicit_target(state, instances, filtered_defs, opts)
	end

	if opts.mode == "definitions" then
		return pick_result(build_definition_items(filtered_defs))
	end

	---@type wiremux.ResolveItem[]
	local items = {}
	if #instances > 0 then
		if opts.mode == "all" and opts.behavior == "pick" then
			items = build_instance_items(sort_instances(instances), state)
		else
			local result = resolve_by_behavior(instances, opts.behavior, state)
			if opts.mode ~= "all" or result.kind == "targets" then
				return result
			end
			items = result.items
		end
	end

	if opts.mode == "instances" then
		return pick_result(items)
	end

	-- Only build adoption/create rows for the auto fallback or an all-mode picker.
	if opts.allow_adopt then
		vim.list_extend(items, build_adopt_items(get_unmanaged_instances(state, opts.filter), state))
	end
	vim.list_extend(items, build_definition_items(filtered_defs))
	local first = items[1]
	if #items == 1 and first.type == "instance" then
		return targets_result({ first.instance })
	end
	return pick_result(items)
end

return M
