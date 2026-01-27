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

	local state = backend.state.get()
	local notify = require("wiremux.utils.notify")

	-- No instances - create one
	if #state.instances == 0 then
		notify.debug("toggle: no instances, creating...")
		return require("wiremux.action.create").create(opts)
	end

	-- Has instances - toggle based on kind
	notify.debug("toggle: has instances, toggling visibility...")
	backend.toggle_visibility(state)
end

return M
