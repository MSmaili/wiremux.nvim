local M = {}

M.validation_pattern = "^[A-Za-z_][A-Za-z0-9_]*$"
M.discovery_pattern = "{([A-Za-z_][A-Za-z0-9_]*)}"
M.materialization_pattern = M.discovery_pattern
M.vim_highlight_pattern = "{[A-Za-z_][A-Za-z0-9_]*}"

---@param name any
---@return boolean
function M.is_valid_name(name)
	return type(name) == "string" and name:match(M.validation_pattern) ~= nil
end

---@param texts string|string[]
---@return table<string, true>
function M.discover(texts)
	if type(texts) == "string" then
		texts = { texts }
	end

	local names = {}
	if type(texts) ~= "table" then
		return names
	end

	for _, text in ipairs(texts) do
		if type(text) == "string" and text:find("{", 1, true) then
			for name in text:gmatch(M.discovery_pattern) do
				names[name] = true
			end
		end
	end
	return names
end

return M
