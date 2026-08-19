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
---@field adapter? string|fun(items: any[], opts: wiremux.picker.Opts, on_choice: fun(item: any?)) Adapter name or custom select function. File picking still uses adapter `files()` when available, otherwise falls back to built-in file selection.
---@field instances? wiremux.config.InstanceConfig
---@field targets? wiremux.config.TargetConfig

---@class wiremux.config.ComposeSessionConfig
---@field width? number Width as fraction of screen (default: 0.6)
---@field height? number Height as fraction of screen (default: 0.4)
---@field title? string Window title (default: " Compose Message ")
---@field border? string|string[] Border style (default: "rounded")
---@field style? string Window style (default: "minimal")
---@field close_behavior? "ask"|"hide"|"discard" Behavior when close action is triggered (default: "ask")
---@field on_new_payload? "ask"|"keep"|"replace"|"append" Behavior when compose opens with a new payload while an unsent draft exists (default: "ask")
---@field wo? table<string, any> Window options (default: { wrap = true, number = false, relativenumber = false })
---@field keymaps? wiremux.config.ComposeKeymaps Custom keymaps

---@class wiremux.config.ComposeUIConfig: wiremux.config.ComposeSessionConfig
---@field capture_placeholders? string[] Global-only names captured into each page's point-in-time snapshot when the page is created.

---@class wiremux.config.ComposeKeymap
---@field [1] string Key
---@field mode? string|string[] Mode(s) (default: "n")
---@field desc? string Description

---@class wiremux.config.ComposeKeymaps
---@field send? wiremux.config.ComposeKeymap|wiremux.config.ComposeKeymap[]
---@field close? wiremux.config.ComposeKeymap|wiremux.config.ComposeKeymap[]
---@field discard? wiremux.config.ComposeKeymap|wiremux.config.ComposeKeymap[]
---@field files? wiremux.config.ComposeKeymap|wiremux.config.ComposeKeymap[]
---@field previous? wiremux.config.ComposeKeymap|wiremux.config.ComposeKeymap[]
---@field next? wiremux.config.ComposeKeymap|wiremux.config.ComposeKeymap[]

---@class wiremux.config.ComposeOptions: wiremux.config.ComposeSessionConfig

---@class wiremux.config.UserOptions
---@field log_level? wiremux.config.LogLevel
---@field targets? { definitions?: table<string, wiremux.target.definition> }
---@field actions? { send?: wiremux.config.ActionConfig, focus?: wiremux.config.ActionConfig, close?: wiremux.config.ActionConfig }
---@field picker? wiremux.config.PickerConfig
---@field context? { resolvers?: table<string, fun(): string> }
---@field ui? { compose?: wiremux.config.ComposeUIConfig }

-- User-facing config (all fields optional)
---@class wiremux.config.ActionConfig
---@field behavior? wiremux.action.Behavior
---@field mode? wiremux.action.SendMode Target source mode (default: "auto")
---@field focus? boolean
---@field submit? boolean
---@field compose? boolean|wiremux.config.ComposeOptions Open compose buffer before sending
---@field filter? wiremux.config.FilterConfig
---@field target? string Target definition name. Sends directly to matching instance, auto-creates if none exist.
---@field pre_keys? string|string[] Keystrokes to send before action (e.g. {"C-c"}, {"i"})
---@field post_keys? string|string[] Keystrokes to send after action (e.g. {"Escape"})

---@class wiremux.target.definition
---@field cmd? string Command to run in the new pane/window
---@field kind? "pane"|"window"|("pane"|"window")[] Target kind (default: "pane"). If table, prompts user to choose.
---@field split? "horizontal"|"vertical" Split direction for panes (default: "horizontal")
---@field split_mode? "before"|"after" Split placement for panes (default: "after")
---@field shell? boolean Run command through shell (default: true)
---@field label? string|fun(inst: wiremux.Instance, index: number): string Custom display label for picker
---@field title? string Custom tmux window / zellij tab name
---@field size? string Custom tmux pane size
---@field startup_timeout? number Max milliseconds to wait for TUI to render before sending (default: 3500)

local defaults = {
	log_level = "warn",
	targets = {
		definitions = {},
	},
	actions = {
		close = { behavior = "pick" },
		create = { behavior = "pick", focus = true },
		send = { behavior = "pick", focus = true, compose = false },
		focus = { behavior = "last", focus = true },
		toggle = { behavior = "last", focus = false },
	},
	context = {
		resolvers = {},
	},
	ui = {
		compose = {
			width = 0.6,
			height = 0.4,
			title = " Compose Message ",
			border = "rounded",
			style = "minimal",
			close_behavior = "ask",
			on_new_payload = "ask",
			wo = {
				wrap = true,
				number = false,
				relativenumber = false,
			},
			capture_placeholders = {
				"file",
				"filename",
				"position",
				"line",
				"selection",
				"this",
			},
			keymaps = {
				send = {
					{ "<C-s>", mode = { "i" }, desc = "Send to target" },
					{ "<CR>", mode = { "n" }, desc = "Send to target" },
				},
				close = {
					{ "q", mode = "n", desc = "Close draft" },
					{ "<Esc>", mode = "n", desc = "Close draft" },
				},
				files = {
					{ "<C-f>", mode = { "n", "i" }, desc = "Insert file" },
				},
				previous = { "<C-p>", mode = "n", desc = "Previous compose page" },
				next = { "<C-n>", mode = "n", desc = "Next compose page" },
			},
		},
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

---@param picker? wiremux.config.PickerConfig
local function validate_picker_callbacks(picker)
	if not picker then
		return
	end
	if picker.instances then
		validate_fn(picker.instances.filter, "picker.instances.filter")
		validate_fn(picker.instances.sort, "picker.instances.sort")
	end
	if picker.targets then
		validate_fn(picker.targets.filter, "picker.targets.filter")
		validate_fn(picker.targets.sort, "picker.targets.sort")
	end
end

---@param opts wiremux.config.UserOptions
---@return table<string, true> known_placeholders
local function configure_resolvers(opts)
	local custom_resolvers = type(opts.context) == "table" and opts.context.resolvers or nil
	local configured_resolvers = {}
	if type(custom_resolvers) == "table" then
		local is_valid_name = require("wiremux.placeholder").is_valid_name
		for name, resolver in pairs(custom_resolvers) do
			if is_valid_name(name) and type(resolver) == "function" then
				configured_resolvers[name] = resolver
			end
		end
	end

	opts.context = type(opts.context) == "table" and opts.context or {}
	opts.context.resolvers = configured_resolvers

	local context = require("wiremux.context")
	context.configure(configured_resolvers)
	local known_placeholders = {}
	for _, name in ipairs(context.list()) do
		known_placeholders[name] = true
	end
	return known_placeholders
end

---@param opts wiremux.config.UserOptions
---@param user_opts wiremux.config.UserOptions
---@param known_placeholders table<string, true>
---@return wiremux.validate.Error[] errors
local function normalize_global_compose(opts, user_opts, known_placeholders)
	local raw_ui = type(user_opts.ui) == "table" and user_opts.ui or nil
	local raw_compose = raw_ui and raw_ui.compose or nil
	local compose, errors = require("wiremux.utils.validate").normalize_global_compose(
		raw_compose,
		defaults.ui.compose,
		known_placeholders
	)
	opts.ui = type(opts.ui) == "table" and opts.ui or {}
	opts.ui.compose = compose
	return errors
end

---@param opts wiremux.config.UserOptions
---@return wiremux.validate.Error[] errors
local function normalize_action_compose(opts)
	local compose = vim.tbl_get(opts, "actions", "send", "compose")
	local normalized, errors = require("wiremux.utils.validate").normalize_action_compose(
		compose,
		defaults.actions.send.compose
	)
	opts.actions.send.compose = normalized
	return errors
end

---@param messages string[]
local function warn_once(messages)
	local notify = require("wiremux.utils.notify")
	local warned = {}
	for _, message in ipairs(messages) do
		if not warned[message] then
			warned[message] = true
			notify.warn(message)
		end
	end
end

function M.setup(user_opts)
	user_opts = user_opts or {}
	M.opts = vim.tbl_deep_extend("force", defaults, user_opts)
	validate_picker_callbacks(M.opts.picker)

	local validate = require("wiremux.utils.validate")
	local warning_messages = validate.validate(M.opts)
	local known_placeholders = configure_resolvers(M.opts)

	local global_errors = normalize_global_compose(M.opts, user_opts, known_placeholders)
	vim.list_extend(warning_messages, validate.error_messages(global_errors))

	local action_errors = normalize_action_compose(M.opts)
	vim.list_extend(warning_messages, validate.error_messages(action_errors))

	warn_once(warning_messages)
end

function M.get()
	return M.opts
end

return M
