local M = {}

---@param opts? wiremux.config.ActionConfig
function M.close(opts)
	opts = opts or {}

	local config = require("wiremux.config")
	local backend = require("wiremux.backend.tmux")
	local action = require("wiremux.core.action")

	action.run({
		prompt = "Close",
		behavior = opts.behavior or config.opts.actions.close.behavior or "pick",
	}, function(targets, state)
		backend.close(targets, state)
	end)
end

return M
