local M = {}

---@param encoded_state string
---@return string[]
function M.set_state(encoded_state)
	return { "set-option", "-s", "@wiremux_state", encoded_state }
end

---@param target string pane or window target name
---@param kind "pane"|"window"
---@return string[]
function M.set_target(target, kind)
	local flag = kind == "window" and "-w" or "-p"
	return { "set-option", flag, "@wiremux_target", target }
end

---@param name? string window name
---@return string[]
function M.new_window(name)
	if name then
		return { "new-window", "-n", name }
	end
	return { "new-window" }
end

---@param direction "horizontal"|"vertical"
---@param target_pane? string pane id to split from
---@return string[]
function M.split_pane(direction, target_pane)
	local cmd = { "split-window", direction == "horizontal" and "-h" or "-v" }
	if target_pane then
		vim.list_extend(cmd, { "-t", target_pane })
	end
	return cmd
end

---@param pane_id string
---@return string[]
function M.select_pane(pane_id)
	return { "select-pane", "-t", pane_id }
end

---@param window_id string
---@return string[]
function M.select_window(window_id)
	return { "select-window", "-t", window_id }
end

---@param target_id string
---@param keys string
---@return string[]
function M.send_keys(target_id, keys)
	return { "send-keys", "-t", target_id, keys, "Enter" }
end

---@param buffer_name string
---@return string[]
function M.load_buffer(buffer_name)
	return { "load-buffer", "-b", buffer_name, "-" }
end

---@param buffer_name string
---@param target_id string
---@return string[]
function M.paste_buffer(buffer_name, target_id)
	return { "paste-buffer", "-b", buffer_name, "-p", "-t", target_id }
end

---@param buffer_name string
---@return string[]
function M.delete_buffer(buffer_name)
	return { "delete-buffer", "-b", buffer_name }
end

---@param pane_id string
---@return string[]
function M.kill_pane(pane_id)
	return { "kill-pane", "-t", pane_id }
end

---@param window_id string
---@return string[]
function M.kill_window(window_id)
	return { "kill-window", "-t", window_id }
end

return M
