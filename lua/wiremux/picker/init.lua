---@class wiremux.picker.Opts
---@field prompt? string Picker prompt text
---@field format_item? fun(item: any): string Format item for display

---@class wiremux.picker.Adapter
---@field available fun(): boolean Check if adapter is usable
---@field select fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))

local M = {}

---@type string[]
M.ADAPTERS = { "fzf-lua" }

---@type fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))?
local cached_select = nil

---@param name string
---@return fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))?
local function try_adapter(name)
	local ok, adapter = pcall(require, "wiremux.picker." .. name)
	if ok and adapter.available and adapter.available() then
		return adapter.select
	end
	return nil
end

---@return fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))
local function auto_detect()
	for _, name in ipairs(M.ADAPTERS) do
		local fn = try_adapter(name)
		if fn then
			return fn
		end
	end

	-- Fallback to vim.ui.select
	return function(items, opts, on_choice)
		vim.ui.select(items, {
			prompt = opts.prompt,
			format_item = opts.format_item,
		}, on_choice)
	end
end

---@return fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))
local function resolve()
	if cached_select then
		return cached_select
	end

	local cfg = require("wiremux.config").get()
	if type(cfg.picker) == "function" then
		cached_select = cfg.picker
	elseif type(cfg.picker) == "string" then
		cached_select = try_adapter(cfg.picker) or auto_detect()
	else
		cached_select = auto_detect()
	end

	return cached_select
end

---Select a single item from a list
---@param items any[]
---@param opts wiremux.picker.Opts
---@param on_choice fun(item: any?) Called with selected item or nil if cancelled
function M.select(items, opts, on_choice)
	resolve()(items, opts, on_choice)
end

---Clear cached picker (useful if config changes)
function M.reset()
	cached_select = nil
end

return M
