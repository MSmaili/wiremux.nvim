local M = {}

local query = require("wiremux.backend.tmux.query")
local action = require("wiremux.backend.tmux.action")
local client = require("wiremux.backend.tmux.client")

---@class wiremux.Instance
---@field id string
---@field kind "pane"|"window"
---@field target string

---@class wiremux.State
---@field origin_pane_id string?
---@field last_used_target_id string?
---@field instances wiremux.Instance[]

---@return wiremux.State
local function empty_state()
	return { instances = {} }
end

---@param inst { id: string, kind: "pane"|"window" }
---@param id_to_target table<string, string>
---@return wiremux.Instance
local function resolve_target(inst, id_to_target)
	return {
		id = inst.id,
		kind = inst.kind,
		target = id_to_target[inst.id] or inst.id,
	}
end

---@param panes_output string
---@param windows_output string
---@return table<string, string> id_to_target (also serves as alive check)
local function parse_tmux_ids(panes_output, windows_output)
	local id_to_target = {}

	for line in (panes_output or ""):gmatch("[^\n]+") do
		local id, target = line:match("^(%%[0-9]+)%s*(.*)$")
		if id then
			id_to_target[id] = target ~= "" and target or id
		end
	end

	for line in (windows_output or ""):gmatch("[^\n]+") do
		local id, target = line:match("^(@[0-9]+)%s*(.*)$")
		if id then
			id_to_target[id] = target ~= "" and target or id
		end
	end

	return id_to_target
end

---@param state wiremux.State
---@return string
local function encode(state)
	local persisted = {
		last_used_target_id = state.last_used_target_id,
		instances = {},
	}

	for _, inst in ipairs(state.instances or {}) do
		if inst.id and inst.kind then
			table.insert(persisted.instances, { id = inst.id, kind = inst.kind })
		end
	end

	return vim.json.encode(persisted)
end

---@param str string
---@return wiremux.State
local function decode(str)
	if not str or str == "" then
		return empty_state()
	end

	local ok, parsed = pcall(vim.json.decode, str)
	if not ok or type(parsed) ~= "table" then
		return empty_state()
	end

	local instances = {}
	for _, inst in ipairs(parsed.instances or {}) do
		if type(inst) == "table" and type(inst.id) == "string" then
			table.insert(instances, {
				id = inst.id,
				kind = inst.kind == "window" and "window" or "pane",
			})
		end
	end

	return {
		origin_pane_id = nil,
		last_used_target_id = type(parsed.last_used_target_id) == "string" and parsed.last_used_target_id or nil,
		instances = instances,
	}
end

---@return wiremux.State
function M.get()
	local results = client.query({
		query.state(),
		query.current_pane(),
		query.list_panes(),
		query.list_windows(),
	})

	local state = decode(results[1] or "")
	local origin_pane_id = vim.trim(results[2] or "")
	local id_to_target = parse_tmux_ids(results[3], results[4])

	state.origin_pane_id = origin_pane_id

	local alive = {}
	for _, inst in ipairs(state.instances) do
		if id_to_target[inst.id] and inst.id ~= origin_pane_id then
			table.insert(alive, resolve_target(inst, id_to_target))
		end
	end
	state.instances = alive

	if state.last_used_target_id and not id_to_target[state.last_used_target_id] then
		state.last_used_target_id = nil
	end

	return state
end

---@param state wiremux.State
function M.set(state)
	client.execute({ action.set_state(encode(state)) })
end

---@param state wiremux.State
---@return string
function M.encode(state)
	return encode(state)
end

return M
