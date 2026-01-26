local M = {}

---Toggle between creating and focusing targets
---If no instances exist, creates from definitions
---If instances exist, focuses the last used one
---@param opts? wiremux.config.ActionConfig
function M.toggle(opts)
	opts = opts or {}

	local backend = require("wiremux.backend").get()
	if not backend then
		return -- Error already shown by backend.get()
	end

	local state = backend.state.get()

	-- No instances - create one
	if #state.instances == 0 then
		return require("wiremux.action.create").create(opts)
	end

	-- Has instances - focus
	return require("wiremux.action.focus").focus(opts)
end

return M
