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

	-- Prefix each row with its index for reliable selection. A preview path goes
	-- after fzf-lua's metadata separator so its configured file previewer can
	-- parse the path while fzf only displays and searches the label.
	local lines = {}
	local nbsp = opts.preview_file and require("fzf-lua.utils").nbsp or nil
	for i, item in ipairs(items) do
		local text = opts.format_item and opts.format_item(item) or tostring(item)
		local path = opts.preview_file and opts.preview_file(item) or nil
		lines[i] = path and string.format("%d\t%s\t%s%s", i, text, nbsp, path) or string.format("%d\t%s", i, text)
	end

	local previewer = opts.preview_file and require("fzf-lua.config").globals.files.previewer or nil

	fzf.fzf_exec(lines, {
		prompt = (opts.prompt or "Select") .. "> ",
		previewer = previewer,
		fzf_opts = {
			["--with-nth"] = opts.preview_file and "2..-2" or "2..", -- Hide index and preview path
			["--nth"] = "1..", -- Search only the transformed display label
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

---@param opts wiremux.picker.Opts
---@param on_choice fun(path: string?)
function M.files(opts, on_choice)
	local fzf = require("fzf-lua")

	fzf.files({
		prompt = (opts.prompt or "Select file") .. "> ",
		actions = {
			["default"] = function(selected)
				if not selected or not selected[1] then
					on_choice(nil)
					return
				end
				on_choice(require("fzf-lua").path.entry_to_file(selected[1]).path)
			end,
		},
	})
end

return M
