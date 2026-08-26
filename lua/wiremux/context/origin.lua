local M = {}

---@class wiremux.context.ResolverOrigin Point-in-time source location for placeholder resolution.
---Every field is captured once, when a send begins, and never refreshed. A resolver that needs
---editor state which cannot be reconstructed later must read it from this record.
---@field bufnr integer Source buffer. May become invalid; use `helpers.buffer_for` to resolve it.
---@field path string Source buffer name, empty for an unnamed buffer.
---@field row integer One-based source row.
---@field col integer Zero-based source byte column.
---@field selection string Visual selection at capture time, or an empty string.
---@field line string Text of the source row at capture time.

---@alias wiremux.context.Resolver fun(origin?: wiremux.context.ResolverOrigin): string?

---@class wiremux.context.Source Frozen source context for one prepared request or compose page.
---@field origin wiremux.context.ResolverOrigin
---@field resolve boolean False when the item set `placeholders = false`, which keeps every
---placeholder literal, including names typed into the draft later.

---Capture the current source location.
---@return wiremux.context.ResolverOrigin
function M.capture()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	return {
		bufnr = bufnr,
		path = vim.api.nvim_buf_get_name(bufnr),
		row = cursor[1],
		col = cursor[2],
		selection = require("wiremux.context.builtins").selection(),
		line = vim.api.nvim_get_current_line(),
	}
end

return M
