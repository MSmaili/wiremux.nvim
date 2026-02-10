local M = {}

local action = require("wiremux.backend.tmux.action")
local client = require("wiremux.backend.tmux.client")
local state = require("wiremux.backend.tmux.state")
local notify = require("wiremux.utils.notify")

local BUFFER_NAME = "wiremux"

---Update statusline from known state (only if already loaded)
---@param st wiremux.State
local function update_statusline(st)
	local statusline = package.loaded["wiremux.statusline"]
	if statusline then
		statusline.update(st)
	end
end

---@param target wiremux.Instance
---@return string[], string[]
function M._focus_cmds(target)
	return action.select_window(target.window_id), action.select_pane(target.id)
end

---@param text string
---@param targets wiremux.Instance[]
---@param opts? { focus?: boolean, submit?: boolean }
---@param st wiremux.State
function M.send(text, targets, opts, st)
	opts = opts or {}
	local clean_text = text:gsub("\t", "  "):gsub("\n$", "")

	local batch = { action.load_buffer(BUFFER_NAME) }

	for _, t in ipairs(targets) do
		table.insert(batch, action.paste_buffer(BUFFER_NAME, t.id))
		if opts.submit then
			table.insert(batch, action.send_keys(t.id, ""))
		end
	end

	if #targets > 0 then
		table.insert(batch, action.delete_buffer(BUFFER_NAME))
	end

	if opts.focus and targets[1] then
		local win_cmd, pane_cmd = M._focus_cmds(targets[1])
		table.insert(batch, win_cmd)
		table.insert(batch, pane_cmd)
	end

	if targets[1] and st.last_used_target_id ~= targets[1].id then
		state.update_last_used(batch, targets[1].id)
	end

	local ok = client.execute(batch, { stdin = clean_text })
	if not ok then
		notify.error("Failed to send text to targets. Check that tmux panes are still active.")
		return
	end
	notify.debug("send: sent to %d targets", #targets)

	if targets[1] then
		st.last_used_target_id = targets[1].id
	end
	update_statusline(st)
end

---@param target wiremux.Instance
function M.focus(target)
	local st = state.get()
	local win_cmd, pane_cmd = M._focus_cmds(target)
	local batch = { win_cmd, pane_cmd }

	if st.last_used_target_id ~= target.id then
		state.update_last_used(batch, target.id)
	end

	local ok = client.execute(batch)
	if ok == nil then
		notify.error(string.format("Failed to focus target %s. Pane may no longer exist.", target.id))
		return
	end

	st.last_used_target_id = target.id
	update_statusline(st)
end

---@param targets wiremux.Instance[]
---@param st wiremux.State
function M.close(targets, st)
	local batch = {}

	local closed_ids = {}
	for _, target in ipairs(targets) do
		closed_ids[target.id] = true
		if target.kind == "window" then
			table.insert(batch, action.kill_window(target.window_id))
		else
			table.insert(batch, action.kill_pane(target.id))
		end
	end

	local ok = client.execute(batch)
	if not ok then
		notify.error("Failed to close targets. Check that tmux panes/windows still exist.")
		return
	end

	notify.debug("close: closed %d targets", #targets)

	local remaining = {}
	for _, inst in ipairs(st.instances) do
		if not closed_ids[inst.id] then
			table.insert(remaining, inst)
		end
	end
	st.instances = remaining

	if st.last_used_target_id and closed_ids[st.last_used_target_id] then
		st.last_used_target_id = remaining[1] and remaining[1].id or nil
	end

	update_statusline(st)
end

---@param target_name string
---@param def wiremux.target.definition
---@param st wiremux.State
---@return wiremux.Instance?
function M.create(target_name, def, st)
	local query = require("wiremux.backend.tmux.query")

	local kind = def.kind or "pane"
	local use_shell = def.shell == nil or def.shell
	local cmd = def.cmd
	local cmds = {}

	if kind == "window" then
		local window_name = def.label or target_name
		table.insert(cmds, action.new_window(window_name, use_shell and nil or cmd))
		table.insert(cmds, query.window_id())
	else
		table.insert(cmds, action.split_pane(def.split or "horizontal", st.origin_pane_id, use_shell and nil or cmd))
		table.insert(cmds, query.pane_id())
	end

	local id = client.execute(cmds)
	if not id or id == "" then
		notify.error(string.format("Failed to create %s. Check tmux configuration and available space.", kind))
		return nil
	end

	state.set_instance_metadata(id, target_name, st.origin_pane_id or "", vim.fn.getcwd(), kind)

	if use_shell and cmd then
		client.execute({ action.send_keys(id, cmd) })
	end

	notify.debug("create: %s %s target=%s", kind, id, target_name)

	local instance = {
		id = id,
		window_id = kind == "window" and id or "",
		target = target_name,
		origin = st.origin_pane_id,
		origin_cwd = vim.fn.getcwd(),
		kind = kind,
		last_used_at = os.time(),
		window_name = (kind == "window" and (def.label or target_name)) or nil,
	}

	table.insert(st.instances, instance)
	st.last_used_target_id = instance.id
	update_statusline(st)

	return instance
end

---Toggle zoom on current pane
function M.toggle_zoom()
	client.execute({ action.resize_pane_zoom() })
end

---Toggle visibility based on instance kind
---@param st wiremux.State
function M.toggle_visibility(st)
	notify.debug("toggle_visibility: last_used_target_id = %s", st.last_used_target_id or "nil")

	if #st.instances == 0 then
		notify.debug("toggle_visibility: no instances available")
		notify.warn("No targets available. Create one with :Wiremux create")
		return
	end

	local target = nil

	if st.last_used_target_id then
		for _, inst in ipairs(st.instances) do
			if inst.id == st.last_used_target_id then
				target = inst
				break
			end
		end
	end

	if not target then
		target = st.instances[1]
		notify.debug("toggle_visibility: last_used not found, falling back to first instance %s", target.id)

		local batch = {}
		state.update_last_used(batch, target.id)
		client.execute(batch)
	end

	-- For windows: switch to target window
	-- For panes: toggle zoom
	if target.kind == "window" then
		notify.debug("toggle_visibility: switching to window %s", target.id)
		client.execute({ action.select_window(target.id) })
	else
		notify.debug("toggle_visibility: toggling zoom")
		M.toggle_zoom()
	end

	st.last_used_target_id = target.id
	update_statusline(st)
end

return M
