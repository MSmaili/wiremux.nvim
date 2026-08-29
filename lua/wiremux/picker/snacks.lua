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
	local picker_items = items
	local format_item = opts.format_item
	local unwrap = function(item)
		return item
	end

	if opts.preview_file then
		picker_items = vim.iter(items)
			:map(function(item)
				return { item = item, file = opts.preview_file(item) }
			end)
			:totable()
		format_item = function(item)
			return opts.format_item and opts.format_item(item.item) or tostring(item.item)
		end
		unwrap = function(item)
			if item == nil then
				return nil
			end
			return item.item
		end
	end

	require("snacks").picker.select(picker_items, {
		prompt = opts.prompt,
		format_item = format_item,
		snacks = opts.preview_file and { preview = "file" } or nil,
	}, function(item)
		on_choice(unwrap(item))
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
