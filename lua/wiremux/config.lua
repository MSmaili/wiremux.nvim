-- Wiremux Configuration
-- Stores user configuration with defaults.

local M = {}

---@alias wiremux.action.Behavior "all"|"pick"|"last"
---@alias wiremux.config.LogLevel "off"|"error"|"warn"|"info"|"debug"

---@class wiremux.config.FilterConfig
---@field instances? fun(inst: wiremux.Instance, state: wiremux.State): boolean
---@field definitions? fun(name: string, def: wiremux.target.definition): boolean

---@class wiremux.config.InstanceConfig
---@field filter? fun(inst: wiremux.Instance, state: wiremux.State): boolean
---@field sort? fun(a: wiremux.Instance, b: wiremux.Instance): boolean

---@class wiremux.config.TargetConfig
---@field filter? fun(name: string, def: wiremux.target.definition): boolean
---@field sort? fun(a: string, b: string): boolean

---@class wiremux.config.PickerConfig
---@field adapter? string|fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?))
---@field instances? wiremux.config.InstanceConfig
---@field targets? wiremux.config.TargetConfig

---@class wiremux.config.UserOptions
---@field log_level? wiremux.config.LogLevel
---@field targets? { definitions?: table<string, wiremux.target.definition> }
---@field actions? { send?: wiremux.config.ActionConfig, focus?: wiremux.config.ActionConfig, close?: wiremux.config.ActionConfig }
---@field picker? wiremux.config.PickerConfig
---@field context? { resolvers?: table<string, fun(): string> }

-- User-facing config (all fields optional)
---@class wiremux.config.ActionConfig
---@field behavior? wiremux.action.Behavior
---@field focus? boolean
---@field submit? boolean
---@field filter? wiremux.config.FilterConfig
---@field target? string Target definition name. Sends directly to matching instance, auto-creates if none exist.

---@class wiremux.target.definition
---@field cmd? string Command to run in the new pane/window
---@field kind? "pane"|"window"|("pane"|"window")[] Target kind (default: "pane"). If table, prompts user to choose.
---@field split? "horizontal"|"vertical" Split direction for panes (default: "horizontal")
---@field shell? boolean Run command through shell (default: true)
---@field label? string|fun(inst: wiremux.Instance, index: number): string Custom display label for picker
---@field title? string Custom tmux window / zellij tab name

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
	picker = {
		adapter = nil,
		instances = {
			filter = function(inst, state)
				return inst.origin == state.origin_pane_id
			end,
			sort = function(a, b)
				return (a.last_used_at or 0) > (b.last_used_at or 0)
			end,
		},
		targets = {
			filter = nil,
			sort = nil,
		},
	},
}

M.opts = vim.deepcopy(defaults)

local function validate_fn(value, name)
	if value ~= nil and type(value) ~= "function" then
		error(string.format("wiremux: %s must be a function", name))
	end
end

function M.setup(user_opts)
	M.opts = vim.tbl_deep_extend("force", defaults, user_opts or {})

	if M.opts.picker then
		local inst = M.opts.picker.instances
		if inst then
			validate_fn(inst.filter, "picker.instances.filter")
			validate_fn(inst.sort, "picker.instances.sort")
		end

		local tgt = M.opts.picker.targets
		if tgt then
			validate_fn(tgt.filter, "picker.targets.filter")
			validate_fn(tgt.sort, "picker.targets.sort")
		end
	end

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
