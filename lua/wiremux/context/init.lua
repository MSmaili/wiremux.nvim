local builtins = require("wiremux.context.builtins")

local M = {}

---@type table<string, wiremux.context.Resolver>
local resolvers = {}

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
	if not ok or result == nil or result == "" then
		return nil
	end

	return result
end

---Expand context variables in text
---@param text string Text with {variable} placeholders
---@return string
function M.expand(text)
	if not text:find("{", 1, true) then
		return text
	end

	local cache = {}
	return (
		text:gsub("{(%w+)}", function(var)
			if cache[var] == nil then
				cache[var] = M.get(var)
			end
			return cache[var]
		end)
	)
end

return M
