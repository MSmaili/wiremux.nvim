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

	local config = require("wiremux.config")
	local action = require("wiremux.core.action")
	local focus = opts.focus ~= nil and opts.focus or config.opts.actions.toggle.focus

	action.run({
		prompt = "Toggle",
		behavior = "last",
		mode = opts.mode or "auto",
		filter = opts.filter,
	}, {
		on_targets = function(targets, state)
			backend.toggle_visibility(state)
			if focus and #targets > 0 then
				backend.focus(targets[1])
			end
		end,
		on_definition = function(name, def, state)
			local inst = backend.create(name, def, state)
			if inst and focus then
				backend.focus(inst)
			end
		end,
	})
end

return M
