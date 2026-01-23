-- Create Action

local M = {}

---@class wiremux.action.CreateOpts
---@field focus? boolean Focus on the created target

---@param opts? wiremux.action.CreateOpts
function M.create(opts)
	opts = opts or {}

	local backend = require("wiremux.backend.tmux")
	local action = require("wiremux.core.action")

	action.run({
		prompt = "Create",
		behavior = "pick",
		mode = "definitions",
	}, function(target)
		if opts.focus then
			backend.focus(target)
		end
	end)
end

return M
