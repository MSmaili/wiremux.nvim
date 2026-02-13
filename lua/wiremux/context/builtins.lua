local h = require("wiremux.context.helpers")

local M = {}

M.file = function()
	return h.current_file()
end

M.filename = function()
	local path = h.current_file()
	if path == "" then
		return ""
	end
	return vim.fn.fnamemodify(path, ":t")
end

M.position = function()
	return h.current_position()
end

M.line = function()
	return vim.api.nvim_get_current_line()
end

M.selection = function()
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

M.diagnostics = function()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local diags = vim.diagnostic.get(0, { lnum = row - 1, namespace = nil })
	if #diags == 0 then
		return "No diagnostics on current line"
	end
	return h.current_file() .. "\n" .. h.format_diagnostics(diags)
end

M.diagnostics_all = function()
	local diags = vim.diagnostic.get(0, { namespace = nil })
	if #diags == 0 then
		return "No diagnostics"
	end
	return h.current_file() .. "\n" .. h.format_diagnostics(diags)
end

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

M.this = function()
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then
		return h.current_position() .. "\n" .. M.selection()
	end
	return h.current_position()
end

M.changes = function()
	local file = h.current_file()
	if file == "" then
		return "No file"
	end
	local result = vim.system({ "git", "diff", "HEAD", "--", file }, { text = true }):wait()
	if result.code ~= 0 or result.stdout == "" then
		return "No changes"
	end
	return result.stdout
end

return M
