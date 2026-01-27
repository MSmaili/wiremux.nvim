local M = {}
---@alias wiremux.ResolveMode "instances"|"definitions"

---@class wiremux.ResolveOpts
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode

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
---@return wiremux.ResolveItem.Instance[]
local function build_instance_items(instances)
	local items = {}
	local counts = {}

	for _, inst in ipairs(instances) do
		local target = inst.target
		counts[target] = (counts[target] or 0) + 1
		table.insert(items, {
			type = "instance",
			instance = inst,
			target = target,
			label = target .. " #" .. counts[target],
		})
	end

	table.sort(items, function(a, b)
		return a.target < b.target
	end)

	return items
end

---@param definitions table<string, wiremux.target.definition>
---@return wiremux.ResolveItem.Definition[]
local function build_definition_items(definitions)
	local items = {}

	for name, def in pairs(definitions or {}) do
		table.insert(items, {
			type = "definition",
			target = name,
			def = def,
			label = "[+] " .. name,
		})
	end

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
	local instances = state.instances
	local last_used = state.last_used_target_id

	-- Definitions mode - only show definitions
	if opts.mode == "definitions" then
		return { kind = "pick", items = build_definition_items(definitions) }
	end

	-- No instances - fallback to definitions
	if #instances == 0 then
		return { kind = "pick", items = build_definition_items(definitions) }
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
