---@class wiremux.picker.Opts
---@field prompt? string Picker prompt text
---@field format_item? fun(item: any): string Format item for display

---@class wiremux.picker.Adapter
---@field available fun(): boolean Check if adapter is usable
---@field select fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))
---@field files? fun(opts: wiremux.picker.Opts, on_choice: fun(path: string?))

local M = {}

---@type string[]
M.ADAPTERS = { "fzf-lua" }

---@type fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))?
local cached_select = nil

---@type fun(opts: wiremux.picker.Opts, on_choice: fun(path: string?))?
local cached_files = nil

---@return table
local function get_picker_config()
	local cfg = require("wiremux.config").get()
	return (cfg and cfg.picker) or {}
end

---@param adapter wiremux.picker.Adapter?
---@return boolean
local function adapter_available(adapter)
	if type(adapter) ~= "table" or type(adapter.available) ~= "function" then
		return false
	end
	local ok, available = pcall(adapter.available)
	return ok and available == true
end

---@param name string
---@return wiremux.picker.Adapter?
local function load_adapter(name)
	local ok, adapter = pcall(require, "wiremux.picker." .. name)
	if not ok or not adapter_available(adapter) then
		return nil
	end
	return adapter
end

---@param name string
---@return fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))?
local function try_adapter(name)
	local adapter = load_adapter(name)
	if adapter and type(adapter.select) == "function" then
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
		opts = opts or {}
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

	local picker_cfg = get_picker_config()

	if type(picker_cfg) ~= "table" then
		cached_select = auto_detect()
	else
		local adapter = picker_cfg.adapter
		if type(adapter) == "function" then
			cached_select = adapter
		elseif type(adapter) == "string" then
			cached_select = try_adapter(adapter) or auto_detect()
		else
			cached_select = auto_detect()
		end
	end

	return cached_select
end

---@param output string?
---@return string[]
local function split_lines(output)
	if type(output) ~= "string" or output == "" then
		return {}
	end

	local trimmed = vim.trim(output)
	if trimmed == "" then
		return {}
	end

	return vim.split(trimmed, "\n", { trimempty = true })
end

---@param files string[]
---@return string[]
local function unique_files(files)
	local seen = {}
	local result = {}

	for _, path in ipairs(files) do
		if type(path) == "string" and path ~= "" and not seen[path] then
			seen[path] = true
			table.insert(result, path)
		end
	end

	return result
end

---@return string[]
local function git_files()
	local result = vim.system({ "git", "ls-files", "--cached", "--others", "--exclude-standard" }, { text = true }):wait()
	if result.code ~= 0 then
		return {}
	end

	return split_lines(result.stdout)
end

---@return string[]
local function glob_files()
	local matches = vim.fn.glob("**/*", false, true)
	local files = {}

	for _, path in ipairs(matches) do
		if vim.fn.isdirectory(path) == 0 then
			table.insert(files, path)
		end
	end

	return files
end

---@return string[]
local function collect_files()
	local files = git_files()
	if #files == 0 then
		files = glob_files()
	end

	return unique_files(files)
end

---@return fun(opts: wiremux.picker.Opts, on_choice: fun(path: string?))
local function fallback_files_picker()
	return function(opts, on_choice)
		opts = opts or {}
		local files = collect_files()
		if #files == 0 then
			on_choice(nil)
			return
		end

		resolve()(files, {
			prompt = opts.prompt or "Select file",
			format_item = function(item)
				return item
			end,
		}, on_choice)
	end
end

---@return fun(opts: wiremux.picker.Opts, on_choice: fun(path: string?))
local function resolve_files()
	if cached_files then
		return cached_files
	end

	local picker_cfg = get_picker_config()
	local adapter_name = picker_cfg and picker_cfg.adapter

	if type(adapter_name) == "string" then
		local adapter = load_adapter(adapter_name)
		if adapter and type(adapter.files) == "function" then
			cached_files = adapter.files
			return cached_files
		end
	end

	for _, name in ipairs(M.ADAPTERS) do
		local adapter = load_adapter(name)
		if adapter and type(adapter.files) == "function" then
			cached_files = adapter.files
			return cached_files
		end
	end

	cached_files = fallback_files_picker()

	return cached_files
end

---Select a single item from a list
---@param items any[]
---@param opts wiremux.picker.Opts
---@param on_choice fun(item: any?) Called with selected item or nil if cancelled
function M.select(items, opts, on_choice)
	opts = opts or {}
	resolve()(items, opts, on_choice)
end

---Pick a file
---@param opts wiremux.picker.Opts
---@param on_choice fun(path: string?) Called with selected file path or nil
function M.files(opts, on_choice)
	opts = opts or {}
	resolve_files()(opts, on_choice)
end

---Clear cached picker (useful if config changes)
function M.reset()
	cached_select = nil
	cached_files = nil
end

return M
