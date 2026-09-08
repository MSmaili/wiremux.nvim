local M = {}

---@param inst wiremux.Instance
---@return string
function M.default_target_name(inst)
	return "pane-" .. (inst.id:match("%d+") or inst.id)
end

---@param inst wiremux.Instance
---@param state wiremux.State
---@return string
function M.location(inst, state)
	local location
	if inst.window_index and inst.pane_index then
		location = string.format("%s:%s", inst.window_index, inst.pane_index)
	elseif inst.window_index then
		location = tostring(inst.window_index)
	else
		location = inst.window_name or inst.id:match("%d+") or inst.id
	end
	if inst.session_id and inst.session_id ~= state.session_id then
		return inst.session_id .. ":" .. location
	end
	return location
end

return M
