local M = {}

local query = require("wiremux.backend.tmux.query")
local action = require("wiremux.backend.tmux.action")
local client = require("wiremux.backend.tmux.client")

---@class wiremux.Pane
---@field session_id string?
---@field id string
---@field window_id string
---@field kind "pane"|"window"
---@field target string?
---@field origin string?
---@field origin_cwd string?
---@field last_used_at number?
---@field window_name string?
---@field window_index number?
---@field pane_index number?
---@field running_command string?

---@class wiremux.Instance : wiremux.Pane
---@field target string

---@class wiremux.State
---@field origin_pane_id string?
---@field session_id string?
---@field last_used_target_id string?
---@field instances wiremux.Instance[]
---@field panes wiremux.Pane[] All panes from the query, including unmanaged panes.

---@param line string
---@return wiremux.Pane?
local function parse_pane_line(line)
	local parts = vim.split(line, ":", { plain = true })
	if #parts < 12 then
		return nil
	end

	local session_id, id, window_id, target, origin, origin_cwd, kind, last_used_at, window_name, window_index, pane_index =
		unpack(parts, 1, 11)
	local running_command = table.concat(parts, ":", 12)

	return {
		session_id = session_id,
		id = id,
		window_id = window_id,
		target = target ~= "" and target or nil,
		origin = origin ~= "" and origin or nil,
		origin_cwd = origin_cwd ~= "" and origin_cwd or nil,
		kind = kind == "window" and "window" or "pane",
		last_used_at = tonumber(last_used_at),
		window_name = window_name ~= "" and window_name or nil,
		window_index = tonumber(window_index),
		pane_index = tonumber(pane_index),
		running_command = running_command ~= "" and running_command or nil,
	}
end

---Parse query results into state
---@param results string[]
---@return wiremux.State
local function parse_state_results(results)
	local current = vim.split(vim.trim(results[1] or ""), ":", { plain = true })
	local origin_pane_id = current[1]
	local session_id = current[2]
	local panes_output = results[2] or ""

	local panes = {}
	local instances = {}
	local last_used_target_id = nil
	local max_used_at = 0

	for line in panes_output:gmatch("[^\n]+") do
		local pane = parse_pane_line(line)
		if pane then
			table.insert(panes, pane)
			if pane.target then
				table.insert(instances, pane)
				if pane.last_used_at and pane.last_used_at > max_used_at then
					max_used_at = pane.last_used_at
					last_used_target_id = pane.id
				end
			end
		end
	end

	return {
		origin_pane_id = origin_pane_id,
		session_id = session_id,
		last_used_target_id = last_used_target_id,
		instances = instances,
		panes = panes,
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

---@param target wiremux.Pane
---@param st wiremux.State
---@param target_name? string Target name to assign when adopting an unmanaged pane.
---@return boolean?
function M.adopt(target, st, target_name)
	target_name = target.target or target_name
	if not target_name or target_name == "" then
		return nil
	end

	local origin = st.origin_pane_id or ""
	local origin_cwd = vim.fn.getcwd()
	local last_used_at = os.time()
	local batch = {}

	if target.target ~= target_name then
		table.insert(batch, action.set_pane_option(target.id, "@wiremux_target", target_name))
		table.insert(batch, action.set_pane_option(target.id, "@wiremux_kind", target.kind or "pane"))
	end

	table.insert(batch, action.set_pane_option(target.id, "@wiremux_origin", origin))
	table.insert(batch, action.set_pane_option(target.id, "@wiremux_origin_cwd", origin_cwd))
	table.insert(batch, action.set_pane_option(target.id, "@wiremux_last_used_at", tostring(last_used_at)))

	local ok = client.execute(batch)

	if not ok then
		return nil
	end

	target.target = target_name
	target.origin = origin ~= "" and origin or nil
	target.origin_cwd = origin_cwd
	target.last_used_at = last_used_at
	st.last_used_target_id = target.id
	st.instances = st.instances or {}
	local exists = vim.iter(st.instances):any(function(inst)
		return inst.id == target.id
	end)
	if not exists then
		table.insert(st.instances, target)
	end
	return true
end

return M
