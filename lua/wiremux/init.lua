local M = {}

--- Setup wiremux with user configuration
---@param opts? wiremux.config.UserOptions
function M.setup(opts)
	require("wiremux.config").setup(opts)
end

---Send text or prompt(s) to target
---@overload fun(text?: string, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem[], opts?: wiremux.config.ActionConfig)
---@param text? string|wiremux.action.SendItem|wiremux.action.SendItem[] Raw template text, single item, or item library. Omit to open or reopen compose.
---@param opts? wiremux.config.ActionConfig Options (behavior, focus, submit, compose, etc.)
function M.send(text, opts)
	return require("wiremux.action.send").send(text, opts)
end

--- Toggle between creating and focusing targets
---@param opts? wiremux.config.ActionConfig
function M.toggle(opts)
	return require("wiremux.action.toggle").toggle(opts)
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

--- Adopt an existing wiremux target in the current tmux session
---@param opts? wiremux.action.AdoptOpts
function M.adopt(opts)
	return require("wiremux.action.adopt").adopt(opts)
end

--- Send text via motion/textobject
---@param opts? wiremux.config.ActionConfig
---@return string
function M.send_motion(opts)
	return require("wiremux.action.send_motion").send_motion(opts)
end

--- Statusline integration for displaying wiremux state
---@type wiremux.statusline
M.statusline = setmetatable({}, {
	__index = function(_, k)
		return require("wiremux.statusline")[k]
	end,
})

return M
