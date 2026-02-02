-- Wiremux Configuration
-- Stores user configuration with defaults.

local M = {}

---@alias wiremux.action.Behavior "all"|"pick"|"last"
---@alias wiremux.config.LogLevel "off"|"error"|"warn"|"info"|"debug"

---@class wiremux.config.FilterConfig
---@field instances? fun(inst: wiremux.Instance, state: wiremux.State): boolean
---@field definitions? fun(def: wiremux.target.definition, name: string, state: wiremux.State): boolean

---@class wiremux.config.UserOptions
---@field log_level? wiremux.config.LogLevel
---@field targets? { definitions?: table<string, wiremux.target.definition> }
---@field actions? { send?: wiremux.config.ActionConfig, focus?: wiremux.config.ActionConfig, close?: wiremux.config.ActionConfig }
---@field picker? string|fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))
---@field context? { resolvers?: table<string, fun(): string> }
---@field filter? wiremux.config.FilterConfig

-- User-facing config (all fields optional)
---@class wiremux.config.ActionConfig
---@field behavior? wiremux.action.Behavior
---@field focus? boolean
---@field submit? boolean
---@field filter? wiremux.config.FilterConfig

---@class wiremux.target.definition
---@field cmd? string Command to run in the new pane/window
---@field kind? "pane"|"window"|("pane"|"window")[] Target kind (default: "pane"). If table, prompts user to choose.
---@field split? "horizontal"|"vertical" Split direction for panes (default: "horizontal")
---@field shell? boolean Run command through shell (default: true)

local defaults = {
	log_level = "warn",
	targets = {
		definitions = {},
	},
	actions = {
		close = { behavior = "pick" },
		create = { behavior = "pick", focus = true },
		send = { behavior = "pick", focus = true },
		focus = { behavior = "last", focus = true },
		toggle = { behavior = "last", focus = false },
	},
	context = {
		resolvers = {},
	},
	filter = {
		instances = function(inst, state)
			return inst.origin == state.origin_pane_id
		end,
	},
}

M.opts = vim.deepcopy(defaults)

function M.setup(user_opts)
	M.opts = vim.tbl_deep_extend("force", defaults, user_opts or {})

	if M.opts.log_level ~= "off" then
		local errors = require("wiremux.utils.validate").validate(M.opts)
		if #errors > 0 then
			local notify = require("wiremux.utils.notify")
			for _, err in ipairs(errors) do
				notify.warn(err)
			end
		end
	end

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
