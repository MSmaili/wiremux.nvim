local builtins = require("wiremux.context.builtins")
local notify = require("wiremux.utils.notify")
local origin_module = require("wiremux.context.origin")
local placeholder = require("wiremux.placeholder")

local M = {}

---@type table<string, wiremux.context.Resolver>
local resolvers = {}

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

---Resolve every placeholder in text against one origin.
---A name without a value stays literal, because `gsub` keeps the match when the
---table lookup gives nil. An empty string removes the placeholder.
---@param text string
---@param origin? wiremux.context.ResolverOrigin
---@return string
function M.resolve(text, origin)
	if not text:find("{", 1, true) then
		return text
	end

	local values = {}
	for _, name in ipairs(placeholder.discover(text)) do
		values[name] = M.get(name, origin)
	end
	return (text:gsub(placeholder.discovery_pattern, values))
end

M.configure()

return M
