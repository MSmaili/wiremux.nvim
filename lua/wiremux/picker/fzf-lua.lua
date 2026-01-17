local M = {}

---@return boolean
function M.available()
	return pcall(require, "fzf-lua")
end

---@param items any[]
---@param opts wiremux.picker.Opts
---@param on_choice fun(item: any?)
function M.select(items, opts, on_choice)
	local fzf = require("fzf-lua")

	-- Build display lines with index prefix for reliable matching
	local lines = {}
	for i, item in ipairs(items) do
		local text = opts.format_item and opts.format_item(item) or tostring(item)
		lines[i] = string.format("%d\t%s", i, text)
	end

	fzf.fzf_exec(lines, {
		prompt = (opts.prompt or "Select") .. "> ",
		fzf_opts = {
			["--with-nth"] = "2..", -- Hide index, show only text
			["--delimiter"] = "\t",
		},
		actions = {
			["default"] = function(selected)
				if not selected or not selected[1] then
					on_choice(nil)
					return
				end
				-- Extract index from selection
				local idx = tonumber(selected[1]:match("^(%d+)\t"))
				if idx and items[idx] then
					on_choice(items[idx])
				else
					on_choice(nil)
				end
			end,
		},
	})
end

return M
