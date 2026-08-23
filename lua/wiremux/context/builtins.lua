local h = require("wiremux.context.helpers")

local M = {}

---@param origin? wiremux.context.ResolverOrigin
---@return string
M.file = function(origin)
	return h.file_for(origin)
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
M.filename = function(origin)
	local path = h.file_for(origin)
	if path == "" then
		return ""
	end
	return vim.fn.fnamemodify(path, ":t")
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
M.position = function(origin)
	return h.position_for(origin)
end

---@param origin? wiremux.context.ResolverOrigin
---@return string?
M.line = function(origin)
	return h.line_for(origin)
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
M.selection = function(origin)
	if origin then
		return origin.selection
	end
	local mode = vim.fn.mode()
	if not mode:match("[vV\22]") then
		return ""
	end
	local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
	if not ok or not lines then
		return ""
	end
	return table.concat(lines, "\n")
end

---@param origin? wiremux.context.ResolverOrigin
---@return string | nil
M.diagnostics = function(origin)
	local bufnr = h.buffer_for(origin)
	if not bufnr then
		return nil
	end
	local row = origin and origin.row or vim.api.nvim_win_get_cursor(0)[1]
	local diags = vim.diagnostic.get(bufnr, { lnum = row - 1, namespace = nil })
	if #diags == 0 then
		return "No diagnostics on current line"
	end
	return h.file_for(origin) .. "\n" .. h.format_diagnostics(diags)
end

---@param origin? wiremux.context.ResolverOrigin
---@return string | nil
M.diagnostics_all = function(origin)
	local bufnr = h.buffer_for(origin)
	if not bufnr then
		return nil
	end
	local diags = vim.diagnostic.get(bufnr, { namespace = nil })
	if #diags == 0 then
		return "No diagnostics"
	end
	return h.file_for(origin) .. "\n" .. h.format_diagnostics(diags)
end

---@return string
M.buffers = function()
	local bufs = {}
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_get_option_value("buflisted", { buf = b }) then
			local name = vim.api.nvim_buf_get_name(b)
			if name ~= "" then
				table.insert(bufs, name)
			end
		end
	end
	return table.concat(bufs, "\n")
end

---@return string
M.quickfix = function()
	local qf = vim.fn.getqflist({ title = 1, items = 1 })
	if #qf.items == 0 then
		return "Quickfix empty"
	end
	local lines = { "Quickfix: " .. (qf.title or "") }
	for _, item in ipairs(qf.items) do
		table.insert(lines, string.format("%s:%d: %s", vim.fn.bufname(item.bufnr), item.lnum, item.text))
	end
	return table.concat(lines, "\n")
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
M.this = function(origin)
	if origin then
		local position = h.position_for(origin)
		return origin.selection ~= "" and position .. "\n" .. origin.selection or position
	end
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then
		return h.position_for() .. "\n" .. M.selection()
	end
	return h.position_for()
end

---@param origin? wiremux.context.ResolverOrigin
---@return string
M.changes = function(origin)
	local file = h.file_for(origin)
	if file == "" then
		return "No file"
	end
	local options = { text = true }
	if origin then
		options.cwd = vim.fs.dirname(file)
	end
	local result = vim.system({ "git", "diff", "HEAD", "--", file }, options):wait()
	if result.code ~= 0 or result.stdout == "" then
		return "No changes"
	end
	return result.stdout
end

return M
