local M = {}

--- Setup wiremux with user configuration
---@param opts? wiremux.config.UserOptions
function M.setup(opts)
	require("wiremux.config").setup(opts)
end

function M.send(text, opts)
	return require("wiremux.action.send").send(text, opts)
end

--- Create a new target from definitions
---@param opts? wiremux.config.ActionConfig
function M.create(opts)
	return require("wiremux.action.create").create(opts)
end

--- Close target pane(s)/window(s)
---@param opts? wiremux.config.ActionConfig
function M.close(opts)
	return require("wiremux.action.close").close(opts)
end

--- Focus on a target pane/window
---@param opts? wiremux.config.ActionConfig
function M.focus(opts)
	return require("wiremux.action.focus").focus(opts)
end

return M
