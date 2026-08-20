local builtins = require("wiremux.context.builtins")
local notify = require("wiremux.utils.notify")
local placeholder = require("wiremux.placeholder")

local M = {}

---@alias wiremux.context.Resolver fun(): string?

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
---@return string? error
local function capture_validation_error(capture)
	if type(capture) ~= "table" then
		return "wiremux placeholder capture must be a table"
	end
	if type(capture.enabled) ~= "boolean" then
		return "wiremux placeholder capture.enabled must be a boolean"
	end
	if type(capture.capture_set) ~= "table" then
		return "wiremux placeholder capture.capture_set must be a table"
	end
	if type(capture.values) ~= "table" then
		return "wiremux placeholder capture.values must be a table"
	end

	for name, attempted in pairs(capture.capture_set) do
		if not placeholder.is_valid_name(name) then
			return "wiremux placeholder capture contains an invalid name"
		end
		if attempted ~= true then
			return "wiremux placeholder capture.capture_set values must be true"
		end
	end
	for name, value in pairs(capture.values) do
		if not placeholder.is_valid_name(name) then
			return "wiremux placeholder capture contains an invalid value name"
		end
		if capture.capture_set[name] ~= true then
			return "wiremux placeholder capture value was not captured"
		end
		if type(value) ~= "string" then
			return "wiremux placeholder capture values must be strings"
		end
	end
end

---Check the complete PlaceholderCapture domain invariant without mutating it.
---@param capture any
---@return boolean
function M.is_valid_capture(capture)
	return capture_validation_error(capture) == nil
end

---@param capture any
local function assert_capture(capture)
	local err = capture_validation_error(capture)
	assert(err == nil, err)
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

---List registered placeholder names in deterministic order.
---@return string[]
function M.list()
	local names = {}
	for name in pairs(resolvers) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

---Get a context value by name.
---Returns nil when the resolver is unknown, fails, or returns a non-string value.
---@param name string
---@return string?
function M.get(name)
	local resolver = resolvers[name]
	if not resolver then
		return nil
	end

	local ok, result = pcall(resolver)
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

---Create an enabled point-in-time capture for placeholders found in text and explicit capture names.
---@param texts string|string[]
---@param capture_names? string[]
---@return wiremux.context.PlaceholderCapture
function M.capture(texts, capture_names)
	local names = placeholder.discover(texts)
	if type(capture_names) == "table" then
		for _, name in ipairs(capture_names) do
			if placeholder.is_valid_name(name) then
				names[name] = true
			end
		end
	end

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
---@return wiremux.context.PlaceholderCapture
function M.extend(capture, text)
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
		local value = M.get(name)
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
