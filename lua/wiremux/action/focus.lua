local M = {}

---@param opts? wiremux.config.ActionConfig
function M.focus(opts)
	opts = opts or {}

	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end
	local config = require("wiremux.config")
	local action = require("wiremux.core.action")

	action.run({
		prompt = "Focus",
		behavior = opts.behavior or config.opts.actions.focus.behavior or "last",
	}, function(targets, _)
		-- Focus only the first target
		if targets[1] then
			backend.focus(targets[1])
		end
	end)
end

return M
