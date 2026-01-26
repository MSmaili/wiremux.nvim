local M = {}

---@param opts? wiremux.config.ActionConfig
function M.focus(opts)
	opts = opts or {}

	local config = require("wiremux.config")
	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end
	local action = require("wiremux.core.action")

	action.run({
		prompt = "Focus",
		behavior = opts.behavior or config.opts.actions.focus.behavior or "last",
		allow_create = false,
	}, function(targets, _)
		-- Focus only the first target
		if targets[1] then
			backend.focus(targets[1])
		end
	end)
end

return M
