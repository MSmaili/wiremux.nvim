local M = {}

---@param pane_id string
---@param key string
---@param value string
---@return string[]
function M.set_pane_option(pane_id, key, value)
	return { "set-option", "-p", "-t", pane_id, key, value }
end

---@param name? string window name
---@param command? string command to run
---@return string[]
function M.new_window(name, command)
	local cmd = { "new-window" }
	if name then
		vim.list_extend(cmd, { "-n", name })
	end
	if command then
		table.insert(cmd, command)
	end
	return cmd
end

---@param direction "horizontal"|"vertical"
---@param target_pane? string pane id to split from
---@param command? string command to run
---@return string[]
function M.split_pane(direction, target_pane, command)
	local cmd = { "split-window", direction == "horizontal" and "-h" or "-v" }
	if target_pane then
		vim.list_extend(cmd, { "-t", target_pane })
	end
	if command then
		table.insert(cmd, command)
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
---@param keys string|string[] e.g. "Enter", { cmd, "Enter" }, { "Escape", "i" }, { "C-c" }
---@return string[]
function M.send_keys(target_id, keys)
	local cmd = { "send-keys", "-t", target_id }
	if type(keys) == "table" then
		vim.list_extend(cmd, keys)
	else
		table.insert(cmd, keys)
	end
	return cmd
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

---@param pane_id? string
---@return string[]
function M.resize_pane_zoom(pane_id)
	local cmd = { "resize-pane", "-Z" }
	if pane_id then
		vim.list_extend(cmd, { "-t", pane_id })
	end
	return cmd
end

return M
