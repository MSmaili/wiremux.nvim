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

---Focus on a target
---@param target wiremux.Instance
function M.focus(target)
	return require("wiremux.backend.tmux.operation").focus(target)
end

---Toggle visibility: zoom for panes, switch for windows
---@param s wiremux.State
function M.toggle_visibility(s)
	return require("wiremux.backend.tmux.operation").toggle_visibility(s)
end

---Close a target pane/window
---@param targets wiremux.Instance
function M.close(targets)
	return require("wiremux.backend.tmux.operation").close(targets, s)
end

return M
