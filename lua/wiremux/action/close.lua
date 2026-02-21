local M = {}

---@param opts? wiremux.config.ActionConfig
function M.close(opts)
	opts = opts or {}

	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end

	local config = require("wiremux.config")
	local action = require("wiremux.core.action")

	action.run({
		prompt = "Close",
		behavior = opts.behavior or config.opts.actions.close.behavior or "pick",
		mode = "instances",
		filter = opts.filter,
		target = opts.target,
	}, {
		on_targets = function(targets, st)
			backend.close(targets, st)
		end,
	})
end

return M
