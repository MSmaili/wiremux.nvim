local M = {}

---Normalize a keymap entry into a list of { key, modes, desc }
---@param entry table? Single keymap or array of keymaps
---@return { key: string, modes: string[], desc?: string }[]
function M.normalize(entry)
	if not entry then
		return {}
	end

	if type(entry[1]) == "string" then
		local modes = entry.mode or "n"
		if type(modes) == "string" then
			modes = { modes }
		end
		return { { key = entry[1], modes = modes, desc = entry.desc } }
	end

	local result = {}
	for _, km in ipairs(entry) do
		local modes = km.mode or "n"
		if type(modes) == "string" then
			modes = { modes }
		end
		table.insert(result, { key = km[1], modes = modes, desc = km.desc })
	end
	return result
end

---Find the first key mapped for a given mode
---@param entry table? Keymap config entry
---@param target_mode string Mode to search for
---@return string?
function M.find_key_for_mode(entry, target_mode)
	for _, km in ipairs(M.normalize(entry)) do
		for _, m in ipairs(km.modes) do
			if m == target_mode then
				return km.key
			end
		end
	end
end

return M
