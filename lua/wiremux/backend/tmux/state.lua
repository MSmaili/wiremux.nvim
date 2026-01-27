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
---@field last_used boolean

---@class wiremux.State
---@field origin_pane_id string?
---@field last_used_target_id string?
---@field instances wiremux.Instance[]

---@param line string
---@return wiremux.Instance?
local function parse_pane_line(line)
	local parts = vim.split(line, ":", { plain = true })
	if #parts ~= 7 then
		return nil
	end

	local id, window_id, target, origin, origin_cwd, kind, last_used = unpack(parts)

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
		last_used = last_used == "true",
	}
end

---@return wiremux.State
function M.get()
	local results = client.query({
		query.current_pane(),
		query.list_panes(),
	})

	local origin_pane_id = vim.trim(results[1] or "")
	local panes_output = results[2] or ""

	local instances = {}
	local last_used_target_id = nil

	for line in panes_output:gmatch("[^\n]+") do
		local inst = parse_pane_line(line)
		if inst and inst.id ~= origin_pane_id then
			table.insert(instances, inst)
			if inst.last_used then
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
		action.set_pane_option(pane_id, "@wiremux_last_used", "true"),
	})
end

---@param batch string[][] Command batch to append to
---@param old_id string? Previous last_used pane ID
---@param new_id string New last_used pane ID
function M.update_last_used(batch, old_id, new_id)
	if old_id and old_id ~= new_id then
		table.insert(batch, action.set_pane_option(old_id, "@wiremux_last_used", "false"))
	end
	table.insert(batch, action.set_pane_option(new_id, "@wiremux_last_used", "true"))
end

return M
