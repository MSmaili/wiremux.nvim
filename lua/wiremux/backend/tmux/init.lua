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

return M
