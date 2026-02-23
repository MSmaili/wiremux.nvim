local M = {}

M.state = {
	get = function()
		return require("wiremux.backend.tmux.state").get()
	end,
	get_async = function(callback)
		return require("wiremux.backend.tmux.state").get_async(callback)
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
---@param s wiremux.State
function M.close(targets, s)
	return require("wiremux.backend.tmux.operation").close(targets, s)
end

---Wait until a newly created pane has rendered its TUI and is ready for input.
---Polls pane content asynchronously; calls callback when stable or timed out.
---@param inst wiremux.Instance
---@param opts? { timeout_ms?: number }
---@param callback fun()
function M.wait_for_ready(inst, opts, callback)
	return require("wiremux.backend.tmux.watch").wait_for_ready(inst.id, callback, opts)
end

return M
