local M = {}

---Get current file path
---@return string
function M.current_file()
	return vim.api.nvim_buf_get_name(0)
end

---Get current cursor position as "filepath:line:col"
---@return string
function M.current_position()
	local path = M.current_file()
	if path == "" then
		path = "[No Name]"
	end
	local pos = vim.api.nvim_win_get_cursor(0)
	return string.format("%s:%d:%d", path, pos[1], pos[2] + 1)
end

---Format diagnostics for display
---@param diags vim.Diagnostic[]
---@return string
function M.format_diagnostics(diags)
	local lines = {}
	for _, d in ipairs(diags) do
		local severity = vim.diagnostic.severity[d.severity] or "UNKNOWN"
		table.insert(lines, string.format("%d:%d [%s] %s", d.lnum + 1, d.col + 1, severity, d.message))
	end
	return table.concat(lines, "\n")
end

return M
