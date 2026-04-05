local builtins = require("wiremux.context.builtins")
local notify = require("wiremux.utils.notify")

local M = {}

---@type table<string, wiremux.context.Resolver>
local resolvers = {}
local UNRESOLVED = {}

---@param texts string|string[]
---@return table<string, true>
local function collect_placeholders(texts)
	if type(texts) == "string" then
		texts = { texts }
	end

	local names = {}
	for _, text in ipairs(texts) do
		if type(text) == "string" and text:find("{", 1, true) then
			for name in text:gmatch("{([%w_]+)}") do
				names[name] = true
			end
		end
	end
	return names
end

-- Register builtins
for name, fn in pairs(builtins) do
	resolvers[name] = fn
end

---Register a custom context resolver
---@param name string
---@param resolver fun():string?
function M.register(name, resolver)
	resolvers[name] = resolver
end

---List all registered placeholder names
---@return string[]
function M.list()
	return vim.tbl_keys(resolvers)
end

---Capture resolved values for placeholders found in text(s)
---@param texts string|string[]
---@return table<string, string>
function M.snapshot(texts)
	local names = collect_placeholders(texts)
	local snapshot = {}
	for name in pairs(names) do
		local value = M.get(name)
		if value ~= nil then
			snapshot[name] = value
		end
	end
	return snapshot
end

---Get a context value by name
---Returns nil if unavailable
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

	if result == nil or result == "" then
		return nil
	end

	return result
end

---Check if a placeholder resolves to a non-empty value
---@param name string Placeholder name (without braces)
---@return boolean
function M.is_available(name)
	return M.get(name) ~= nil
end

---Expand context variables in text
---@param text string Text with {variable} placeholders
---@param snapshot? table<string, string> Optional frozen values to prefer
---@return string
function M.expand(text, snapshot)
	if not text:find("{", 1, true) then
		return text
	end

	local cache = {}
	return (
		text:gsub("{([%w_]+)}", function(var)
			if cache[var] == nil then
				local value = (snapshot and snapshot[var]) or M.get(var)
				cache[var] = value == nil and UNRESOLVED or value
			end
			if cache[var] == UNRESOLVED then
				return nil
			end
			return cache[var]
		end)
	)
end

return M
