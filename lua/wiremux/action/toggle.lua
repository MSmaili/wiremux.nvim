local M = {}

---Toggle between creating and hiding/showing targets
---If no instances exist, creates from definitions
---For panes: toggles zoom on origin pane (hide/show target)
---For windows: switches between origin and target window
---@param opts? wiremux.config.ActionConfig
function M.toggle(opts)
	opts = opts or {}

	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end

	local action = require("wiremux.core.action")

	action.run({
		prompt = "Toggle",
		behavior = "last",
		mode = opts.mode or "auto",
		filter = opts.filter,
	}, {
		on_targets = function(_, state)
			backend.toggle_visibility(state)
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
