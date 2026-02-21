local M = {}

---Create a new target from definitions
---@param opts? wiremux.config.ActionConfig
function M.create(opts)
	opts = opts or {}

	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end

	local action = require("wiremux.core.action")

	action.run({
		prompt = "Create",
		behavior = opts.behavior,
		mode = "definitions",
		filter = opts.filter,
		target = opts.target,
	}, {
		on_definition = function(name, def, state)
			backend.create(name, def, state)
		end,
	})
end

return M
