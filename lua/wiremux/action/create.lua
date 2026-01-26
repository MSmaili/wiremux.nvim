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
		behavior = "pick",
		mode = "definitions",
	}, function(_, _)
		-- Target is already created by resolve_choice
		-- Just a placeholder - could add post-creation logic here
	end)
end

return M
