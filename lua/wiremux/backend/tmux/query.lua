local M = {}

---@return string[]
function M.state()
	return { "show-option", "-sqv", "@wiremux_state" }
end

---@return string[]
function M.current_pane()
	return { "display", "-p", "#{pane_id}" }
end

---@return string[]
function M.list_panes()
	return { "list-panes", "-s", "-F", "#{pane_id} #{@wiremux_target}" }
end

---@return string[]
function M.list_windows()
	return { "list-windows", "-F", "#{window_id} #{@wiremux_target}" }
end

---@return string[]
function M.pane_id()
	return { "display", "-p", "#{pane_id}" }
end

---@return string[]
function M.window_id()
	return { "display", "-p", "#{window_id}" }
end

return M
