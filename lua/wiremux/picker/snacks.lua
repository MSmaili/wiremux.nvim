local M = {}

---@return boolean
function M.available()
	local ok, snacks = pcall(require, "snacks")
	return ok and type(snacks.picker) == "table"
end

---@param items any[]
---@param opts wiremux.picker.Opts
---@param on_choice fun(item: any?)
function M.select(items, opts, on_choice)
	local snacks = require("snacks")

	snacks.picker.select(items, {
		prompt = opts.prompt,
		format_item = opts.format_item,
	}, function(item)
		on_choice(item)
	end)
end

---@param opts wiremux.picker.Opts
---@param on_choice fun(path: string?)
function M.files(opts, on_choice)
	local snacks = require("snacks")
	local completed = false

	snacks.picker.files({
		prompt = opts.prompt or "Select file",
		confirm = function(picker, item)
			if completed then
				return
			end
			completed = true
			picker:close()
			if not item then
				on_choice(nil)
				return
			end

			local path = item.file
			if not path then
				path = require("snacks.picker.util").path(item)
			end
			on_choice(path)
		end,
		on_close = function()
			if completed then
				return
			end
			completed = true
			on_choice(nil)
		end,
	})
end

return M
