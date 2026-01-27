local M = {}

---Toggle between creating and hiding/showing targets
---If no instances exist, creates from definitions
---For panes: toggles zoom on origin pane (hide/show target)
---For windows: switches between origin and target window
---@param opts? wiremux.config.ActionConfig
function M.toggle(opts)
	opts = opts or {}

	local action = require("wiremux.core.action")
	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end

	action.run({
		prompt = "Toggle",
		behavior = "last",
		filter = opts.filter,
	}, function(_, state)
		if backend then
			backend.toggle_visibility(state)
		end
	end)
end

return M
