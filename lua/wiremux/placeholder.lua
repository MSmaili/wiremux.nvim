local M = {}

local name_pattern = "[A-Za-z_][A-Za-z0-9_]*"
M.validation_pattern = "^" .. name_pattern .. "$"
M.discovery_pattern = "{(" .. name_pattern .. ")}"
M.vim_highlight_pattern = "{" .. name_pattern .. "}"

---@param name any
---@return boolean
function M.is_valid_name(name)
	return type(name) == "string" and name:match(M.validation_pattern) ~= nil
end

---@param text string
---@param column integer Zero-based byte column.
---@return string? name
function M.at(text, column)
	local offset = 1
	while true do
		local first, last, name = text:find(M.discovery_pattern, offset)
		if first == nil then
			return nil
		end
		if column >= first - 1 and column <= last - 1 then
			return name
		end
		offset = last + 1
	end
end

---@param text string
---@return string[] Sorted unique names.
function M.discover(text)
	local names, seen = {}, {}
	for name in text:gmatch(M.discovery_pattern) do
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

return M
