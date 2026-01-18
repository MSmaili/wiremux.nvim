local M = {}

local action = require("wiremux.backend.tmux.action")
local client = require("wiremux.backend.tmux.client")
local state = require("wiremux.backend.tmux.state")
local notify = require("wiremux.utils.notify")

local BUFFER_NAME = "wiremux"

---@param text string
---@param targets wiremux.Instance[]
---@param opts? { focus?: boolean }
---@param st wiremux.State
function M.send(text, targets, opts, st)
	opts = opts or {}
	-- remove tabs and newlines, tabs because it is spawing tab for some commands
	local clean_text = text:gsub("\t", "  "):gsub("\n$", "")

	local batch = { action.load_buffer(BUFFER_NAME) }

	for _, t in ipairs(targets) do
		table.insert(batch, action.paste_buffer(BUFFER_NAME, t.id))
	end

	if #targets > 0 then
		table.insert(batch, action.delete_buffer(BUFFER_NAME))
	end

	if opts.focus and targets[1] then
		table.insert(batch, M._focus_cmd(targets[1]))
	end

	if targets[1] and st.last_used_target_id ~= targets[1].id then
		st.last_used_target_id = targets[1].id
		table.insert(batch, action.set_state(state.encode(st)))
	end

	local ok = client.execute(batch, { stdin = clean_text })
	if not ok then
		notify.error("send: failed to send to targets")
		return
	end
	notify.debug("send: sent to %d targets", #targets)
end

---@param target wiremux.Instance
---@return string[]
function M._focus_cmd(target)
	if target.kind == "window" then
		return action.select_window(target.id)
	end
	return action.select_pane(target.id)
end

---@param target wiremux.Instance
function M.focus(target)
	client.execute({ M._focus_cmd(target) })
end

---@param target_name string
---@param def wiremux.target.definition
---@param st wiremux.State
---@return wiremux.Instance?
function M.create(target_name, def, st)
	local query = require("wiremux.backend.tmux.query")

	local kind = def.kind or "pane"
	local cmds = {}

	if kind == "window" then
		table.insert(cmds, action.new_window(target_name))
		if target_name then
			table.insert(cmds, action.set_target(target_name, "window"))
		end
		table.insert(cmds, query.window_id())
	else
		table.insert(cmds, action.split_pane(def.split or "vertical", st.origin_pane_id))
		if target_name then
			table.insert(cmds, action.set_target(target_name, "pane"))
		end
		table.insert(cmds, query.pane_id())
	end

	local id = client.execute(cmds)
	if not id or id == "" then
		notify.error(string.format("create: failed to create %s", kind))
		return nil
	end

	if def.cmd then
		client.execute({ action.send_keys(id, def.cmd) })
	end

	local instance = { id = id, target = target_name or id, kind = kind }
	table.insert(st.instances, instance)

	state.set(st)
	notify.debug("create: %s %s target=%s", kind, id, instance.target)
	return instance
end

return M
