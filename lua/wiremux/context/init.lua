local builtins = require("wiremux.context.builtins")
local notify = require("wiremux.utils.notify")
local origin_module = require("wiremux.context.origin")
local placeholder = require("wiremux.placeholder")

local M = {}

---@class wiremux.context.PlaceholderCapture Point-in-time placeholder capture owned by one prepared request or compose page.
---@field enabled boolean Whether extension and materialization are enabled.
---@field results table<string, string|false> Resolved strings, including empty strings, or false for attempted unavailable names.

---@type table<string, wiremux.context.Resolver>
local resolvers = {}

---Load-bearing: `M.materialize` passes `results` to `gsub`, which throws on non-string values.
---@param capture any
local function assert_capture(capture)
	assert(type(capture) == "table", "wiremux placeholder capture must be a table")
	assert(type(capture.enabled) == "boolean", "wiremux placeholder capture.enabled must be a boolean")
	assert(type(capture.results) == "table", "wiremux placeholder capture.results must be a table")
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
	return origin_module.capture()
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
		-- Copied because origin crosses into third-party resolver code.
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
---`memo` shares one resolver result per name across the candidates of one send invocation.
---@param text string
---@param memo? table<string, string|false> Per-invocation resolver results, mutated in place.
---@return wiremux.context.PlaceholderCapture
function M.capture(text, memo)
	local capture = { enabled = true, results = {} }
	for _, name in ipairs(placeholder.discover(text)) do
		local result = memo and memo[name]
		if result == nil then
			result = M.get(name) or false
			if memo then
				memo[name] = result
			end
		end
		capture.results[name] = result
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
	assert_capture(capture)
	local extended = vim.deepcopy(capture)
	assert(type(text) == "string", "wiremux placeholder text must be a string")
	if not extended.enabled or not text:find("{", 1, true) then
		return extended
	end

	for _, name in ipairs(placeholder.discover(text)) do
		if extended.results[name] == nil then
			extended.results[name] = M.get(name, origin) or false
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

	return (text:gsub(placeholder.discovery_pattern, capture.results))
end

M.configure()

return M
