-- Wiremux Configuration
-- Stores user configuration with defaults.

local M = {}

---@alias wiremux.action.Behavior "all"|"pick"|"last"
---@alias wiremux.config.LogLevel "off"|"error"|"warn"|"info"|"debug"

---@class wiremux.config.UserOptions
---@field log_level? wiremux.config.LogLevel
---@field targets? { definitions?: table<string, wiremux.target.definition> }
---@field actions? { send?: wiremux.config.ActionConfig, focus?: wiremux.config.ActionConfig, close?: wiremux.config.ActionConfig }
---@field picker? string|fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))
---@field context? { resolvers?: table<string, fun(): string> }

-- User-facing config (all fields optional)
---@class wiremux.config.ActionConfig
---@field behavior? wiremux.action.Behavior
---@field focus? boolean
---@field allow_create? boolean

---@class wiremux.target.definition
---@field cmd? string Command to run in the new pane/window
---@field kind? "pane"|"window" Target kind (default: "pane")
---@field split? "horizontal"|"vertical" Split direction for panes (default: "vertical")

local defaults = {
	log_level = "warn",
	targets = {
		definitions = {},
	},
	actions = {
		send = { behavior = "pick", focus = true },
		focus = { behavior = "last", focus = true },
		close = { behavior = "pick" },
	},
	context = {
		resolvers = {},
	},
}

M.opts = vim.deepcopy(defaults)

function M.setup(user_opts)
	M.opts = vim.tbl_deep_extend("force", defaults, user_opts or {})
	require("wiremux.utils.validate").validate(M.opts)

	-- Register custom context resolvers
	if M.opts.context and M.opts.context.resolvers then
		local context = require("wiremux.context")
		for name, resolver in pairs(M.opts.context.resolvers) do
			context.register(name, resolver)
		end
	end
end

function M.get()
	return M.opts
end

return M
