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
		mode = "instances",
		filter = opts.filter,
		target = opts.target,
	}, {
		on_targets = function(targets, _)
			backend.focus(targets[1])
		end,
		on_definition = function(name, def, state)
			local inst = backend.create(name, def, state)
			if inst then
				backend.focus(inst)
			end
		end,
	})
end

return M
