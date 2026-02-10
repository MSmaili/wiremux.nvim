local M = {}

local query = require("wiremux.backend.tmux.query")
local action = require("wiremux.backend.tmux.action")
local client = require("wiremux.backend.tmux.client")

---@class wiremux.Instance
---@field id string
---@field window_id string
---@field kind "pane"|"window"
---@field target string
---@field origin string
---@field origin_cwd string
---@field last_used_at number?
---@field window_name string?

---@class wiremux.State
---@field origin_pane_id string?
---@field last_used_target_id string?
---@field instances wiremux.Instance[]

---@param line string
---@return wiremux.Instance?
local function parse_pane_line(line)
	local parts = vim.split(line, ":", { plain = true })
	if #parts < 8 then
		return nil
	end

	local id, window_id, target, origin, origin_cwd, kind, last_used_at, window_name = unpack(parts, 1, 8)

	if not target or target == "" then
		return nil
	end

	return {
		id = id,
		window_id = window_id,
		target = target,
		origin = origin ~= "" and origin or nil,
		origin_cwd = origin_cwd ~= "" and origin_cwd or nil,
		kind = kind == "window" and "window" or "pane",
		last_used_at = tonumber(last_used_at),
		window_name = window_name ~= "" and window_name or nil,
	}
end

---Parse query results into state
---@param results string[]
---@return wiremux.State
local function parse_state_results(results)
	local origin_pane_id = vim.trim(results[1] or "")
	local panes_output = results[2] or ""

	local instances = {}
	local last_used_target_id = nil
	local max_used_at = 0

	for line in panes_output:gmatch("[^\n]+") do
		local inst = parse_pane_line(line)
		if inst then
			table.insert(instances, inst)
			if inst.last_used_at and inst.last_used_at > max_used_at then
				max_used_at = inst.last_used_at
				last_used_target_id = inst.id
			end
		end
	end

	return {
		origin_pane_id = origin_pane_id,
		last_used_target_id = last_used_target_id,
		instances = instances,
	}
end

---@return wiremux.State
function M.get()
	local results = client.query({
		query.current_pane(),
		query.list_panes(),
	})

	return parse_state_results(results)
end

---Get state asynchronously
---@param callback fun(state: wiremux.State?) Callback with state or nil on error
function M.get_async(callback)
	client.query_async({
		query.current_pane(),
		query.list_panes(),
	}, function(results)
		if not results then
			callback(nil)
			return
		end
		callback(parse_state_results(results))
	end)
end

---@param pane_id string
---@param target string
---@param origin string
---@param origin_cwd string
---@param kind "pane"|"window"
function M.set_instance_metadata(pane_id, target, origin, origin_cwd, kind)
	client.execute({
		action.set_pane_option(pane_id, "@wiremux_target", target),
		action.set_pane_option(pane_id, "@wiremux_origin", origin),
		action.set_pane_option(pane_id, "@wiremux_origin_cwd", origin_cwd),
		action.set_pane_option(pane_id, "@wiremux_kind", kind),
		action.set_pane_option(pane_id, "@wiremux_last_used_at", tostring(os.time())),
	})
end

---@param batch string[][] Command batch to append to
---@param new_id string Pane ID to mark as used
function M.update_last_used(batch, new_id)
	table.insert(batch, action.set_pane_option(new_id, "@wiremux_last_used_at", tostring(os.time())))
end

return M
