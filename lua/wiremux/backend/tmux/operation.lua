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

return M
