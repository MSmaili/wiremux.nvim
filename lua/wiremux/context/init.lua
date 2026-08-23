local builtins = require("wiremux.context.builtins")
local notify = require("wiremux.utils.notify")
local placeholder = require("wiremux.placeholder")

local M = {}

---@class wiremux.context.ResolverOrigin Point-in-time source location for deferred placeholder resolution.
---@field bufnr integer
---@field path string
---@field row integer One-based source row.
---@field col integer Zero-based source byte column.
---@field selection string Point-in-time visual selection, or an empty string.

---@alias wiremux.context.Resolver fun(origin?: wiremux.context.ResolverOrigin): string?

---@class wiremux.context.PlaceholderCapture Point-in-time placeholder capture owned by one prepared request or compose page.
---@field enabled boolean Whether extension and materialization are enabled.
---@field capture_set table<string, true> Every attempted name, including unavailable outcomes that must not be retried.
---@field values table<string, string> Successful string results captured at that point in time, including empty strings.

---@type table<string, wiremux.context.Resolver>
local resolvers = {}

---@param names table<string, true>
---@return string[]
local function sorted_names(names)
	local result = {}
	for name in pairs(names) do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

---@generic T
---@param source table<string, T>
---@return table<string, T>
local function clone_map(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

---@param capture any
local function assert_capture(capture)
	assert(type(capture) == "table", "wiremux placeholder capture must be a table")
	assert(type(capture.enabled) == "boolean", "wiremux placeholder capture.enabled must be a boolean")
	assert(type(capture.capture_set) == "table", "wiremux placeholder capture.capture_set must be a table")
	assert(type(capture.values) == "table", "wiremux placeholder capture.values must be a table")

	for name, attempted in pairs(capture.capture_set) do
		assert(placeholder.is_valid_name(name), "wiremux placeholder capture contains an invalid name")
		assert(attempted == true, "wiremux placeholder capture.capture_set values must be true")
	end
	for name, value in pairs(capture.values) do
		assert(placeholder.is_valid_name(name), "wiremux placeholder capture contains an invalid value name")
		assert(capture.capture_set[name] == true, "wiremux placeholder capture value was not captured")
		assert(type(value) == "string", "wiremux placeholder capture values must be strings")
	end
end

---@param capture wiremux.context.PlaceholderCapture
---@return wiremux.context.PlaceholderCapture
local function clone_capture(capture)
	assert_capture(capture)
	return {
		enabled = capture.enabled,
		capture_set = clone_map(capture.capture_set),
		values = clone_map(capture.values),
	}
end

---Replace all custom context resolvers while preserving builtins.
---@param custom_resolvers? table<string, wiremux.context.Resolver>
---@return table<string, wiremux.context.Resolver> configured_custom_resolvers
function M.configure(custom_resolvers)
	local configured = {}
	for name, resolver in pairs(builtins) do
		configured[name] = resolver
	end

	local configured_custom_resolvers = {}
	if type(custom_resolvers) == "table" then
		for name, resolver in pairs(custom_resolvers) do
			if placeholder.is_valid_name(name) and type(resolver) == "function" then
				configured[name] = resolver
				configured_custom_resolvers[name] = resolver
			end
		end
	end

	resolvers = configured
	return configured_custom_resolvers
end

---Capture the current source location for deferred resolution.
---@return wiremux.context.ResolverOrigin
function M.capture_origin()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	return {
		bufnr = bufnr,
		path = vim.api.nvim_buf_get_name(bufnr),
		row = cursor[1],
		col = cursor[2],
		selection = builtins.selection(),
	}
end

---Get a context value by name.
---Returns nil when the resolver is unknown, fails, or returns a non-string value.
---@param name string
---@param origin? wiremux.context.ResolverOrigin
---@return string?
function M.get(name, origin)
	local resolver = resolvers[name]
	if not resolver then
		return nil
	end

	local ok, result
	if origin then
		ok, result = pcall(resolver, vim.deepcopy(origin))
	else
		ok, result = pcall(resolver)
	end
	if not ok then
		notify.debug("context resolver '%s' failed: %s", name, tostring(result))
		return nil
	end
	if result ~= nil and type(result) ~= "string" then
		notify.debug("context resolver '%s' returned %s, expected string", name, type(result))
		return nil
	end
	return result
end

---Check if a placeholder resolves to a non-empty value.
---@param name string Placeholder name (without braces)
---@return boolean
function M.is_available(name)
	local value = M.get(name)
	return value ~= nil and value ~= ""
end

---Create an enabled point-in-time capture for placeholders found in text.
---@param texts string|string[]
---@return wiremux.context.PlaceholderCapture
function M.capture(texts)
	local names = placeholder.discover(texts)

	local capture = {
		enabled = true,
		capture_set = {},
		values = {},
	}
	for _, name in ipairs(sorted_names(names)) do
		capture.capture_set[name] = true
		local value = M.get(name)
		if value ~= nil then
			capture.values[name] = value
		end
	end
	return capture
end

---Create a working clone and resolve names in text that were not previously attempted.
---The stored input capture is never mutated.
---@param capture wiremux.context.PlaceholderCapture
---@param text string
---@param origin? wiremux.context.ResolverOrigin
---@return wiremux.context.PlaceholderCapture
function M.extend(capture, text, origin)
	local extended = clone_capture(capture)
	assert(type(text) == "string", "wiremux placeholder text must be a string")
	if not extended.enabled or not text:find("{", 1, true) then
		return extended
	end

	local names = placeholder.discover(text)
	for name in pairs(extended.capture_set) do
		names[name] = nil
	end
	for _, name in ipairs(sorted_names(names)) do
		extended.capture_set[name] = true
		local value = M.get(name, origin)
		if value ~= nil then
			extended.values[name] = value
		end
	end
	return extended
end

---Materialize complete text through capture lookup only, without invoking a resolver.
---@param text string
---@param capture wiremux.context.PlaceholderCapture
---@return string
function M.materialize(text, capture)
	assert(type(text) == "string", "wiremux placeholder text must be a string")
	assert_capture(capture)
	if not capture.enabled or not text:find("{", 1, true) then
		return text
	end

	return (
		text:gsub(placeholder.materialization_pattern, function(name)
			local value = capture.values[name]
			if value == nil then
				return nil
			end
			return value
		end)
	)
end

M.configure()

return M
