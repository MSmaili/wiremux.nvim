local M = {}

---@param origin? wiremux.context.ResolverOrigin
---@return integer? bufnr
function M.buffer_for(origin)
	if not origin then
		return vim.api.nvim_get_current_buf()
	end
	if vim.api.nvim_buf_is_valid(origin.bufnr) and vim.api.nvim_buf_is_loaded(origin.bufnr) then
		return origin.bufnr
	end
	if origin.path ~= "" then
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) == origin.path then
				return bufnr
			end
		end
	end
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
function M.file_for(origin)
	return origin and origin.path or vim.api.nvim_buf_get_name(0)
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
function M.position_for(origin)
	local path = M.file_for(origin)
	if path == "" then
		path = "[No Name]"
	end
	local row, col
	if origin then
		row, col = origin.row, origin.col
	else
		local cursor = vim.api.nvim_win_get_cursor(0)
		row, col = cursor[1], cursor[2]
	end
	return string.format("%s:%d:%d", path, row, col + 1)
end

---@param origin? wiremux.context.ResolverOrigin
---@return string?
function M.line_for(origin)
	if not origin then
		return vim.api.nvim_get_current_line()
	end
	local bufnr = M.buffer_for(origin)
	if not bufnr then
		return nil
	end
	return vim.api.nvim_buf_get_lines(bufnr, origin.row - 1, origin.row, false)[1]
end

---Format diagnostics for display
---@param diags { lnum: integer, col: integer, severity: integer|string, message: string }[]
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
