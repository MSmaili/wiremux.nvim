local M = {}

M.state = {
	get = function()
		return require("wiremux.backend.tmux.state").get()
	end,
	set = function(s)
		return require("wiremux.backend.tmux.state").set(s)
	end,
}

function M.send(text, targets, opts, s)
	return require("wiremux.backend.tmux.operation").send(text, targets, opts, s)
end

---Create a new target from a definition
---@param target_name string
---@param def wiremux.target.definition
---@param s wiremux.State
---@return wiremux.Instance?
function M.create(target_name, def, s)
	return require("wiremux.backend.tmux.operation").create(target_name, def, s)
end

return M
