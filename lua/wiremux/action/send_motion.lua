local M = {}

local motion_opts = nil

local function send_operator(type)
	local start_mark, end_mark

	-- Visual mode passes 'v', 'V', or '\22' (ctrl-v for block)
	-- Operator mode passes 'char', 'line', or 'block'
	if type == "v" or type == "V" or type == "\22" then
		start_mark, end_mark = "<", ">"
	else
		start_mark, end_mark = "[", "]"
	end

	local start = vim.api.nvim_buf_get_mark(0, start_mark)
	local finish = vim.api.nvim_buf_get_mark(0, end_mark)
	local lines = vim.api.nvim_buf_get_lines(0, start[1] - 1, finish[1], false)

	if #lines == 0 then
		motion_opts = nil
		return
	end

	if #lines == 1 then
		lines[1] = lines[1]:sub(start[2] + 1, finish[2] + 1)
	else
		lines[1] = lines[1]:sub(start[2] + 1)
		lines[#lines] = lines[#lines]:sub(1, finish[2] + 1)
	end

	local text = table.concat(lines, "\n")
	if text ~= "" then
		require("wiremux").send(text, motion_opts)
	end
	motion_opts = nil
end

---Setup operator for sending text via motion
---@param opts? wiremux.config.ActionConfig
---@return string
function M.send_motion(opts)
	motion_opts = opts
	vim.opt.operatorfunc = "v:lua.require'wiremux.action.send_motion'.operator"
	return "g@"
end

M.operator = send_operator

return M
