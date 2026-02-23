local M = {}

local PANE_FORMAT =
	"#{pane_id}:#{window_id}:#{@wiremux_target}:#{@wiremux_origin}:#{@wiremux_origin_cwd}:#{@wiremux_kind}:#{@wiremux_last_used_at}:#{window_name}:#{pane_current_command}"

---@return string[]
function M.current_pane()
	return { "display", "-p", "#{pane_id}" }
end

---@return string[]
function M.list_panes()
	return { "list-panes", "-a", "-F", PANE_FORMAT }
end

---@return string[]
function M.pane_id()
	return { "display", "-p", "#{pane_id}" }
end

---@return string[]
function M.window_id()
	return { "display", "-p", "#{window_id}" }
end

---Capture the visible text content of a pane
---@param pane_id string
---@return string[]
function M.capture_pane(pane_id)
	return { "capture-pane", "-p", "-t", pane_id }
end

return M
