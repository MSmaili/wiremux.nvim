local M = {}

---@class wiremux.action.RunOpts
---@field prompt string
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode
---@field filter? wiremux.config.FilterConfig

---@class wiremux.action.Callbacks
---@field on_targets? fun(targets: wiremux.Instance[], state: wiremux.State)
---@field on_definition? fun(name: string, def: wiremux.target.definition, state: wiremux.State)

---Resolve kind when definition has multiple kinds (table).
---Shows a picker to let the user choose, then calls on_resolved with a
---copy of the definition where kind is the chosen string value.
---If kind is already a string or nil, calls on_resolved immediately.
---@param def wiremux.target.definition
---@param on_resolved fun(def: wiremux.target.definition)
local function resolve_kind(def, on_resolved)
	local kind = def.kind
	if kind == nil or type(kind) == "string" then
		on_resolved(def)
		return
	end

	local picker = require("wiremux.picker")
	local items = vim.iter(kind)
		:map(function(k)
			return { label = k, value = k }
		end)
		:totable()

	vim.defer_fn(function()
		picker.select(items, {
			prompt = "Select kind",
			format_item = function(item)
				return item.label
			end,
		}, function(choice)
			if not choice then
				return
			end
			on_resolved(vim.tbl_extend("force", def, { kind = choice.value }))
		end)
	end, 50)
end

---Filter picker items to only include types the callbacks can handle.
---@param items wiremux.ResolveItem[]
---@param callbacks wiremux.action.Callbacks
---@return wiremux.ResolveItem[]
local function filter_items_by_callbacks(items, callbacks)
	return vim.iter(items)
		:filter(function(item)
			if item.type == "instance" then
				return callbacks.on_targets ~= nil
			elseif item.type == "definition" then
				return callbacks.on_definition ~= nil
			end
			return false
		end)
		:totable()
end

---Dispatch a single picked item to the appropriate callback.
---@param choice wiremux.ResolveItem
---@param callbacks wiremux.action.Callbacks
---@param state wiremux.State
local function dispatch_choice(choice, callbacks, state)
	if choice.type == "instance" then
		if callbacks.on_targets then
			callbacks.on_targets({ choice.instance }, state)
		end
	elseif choice.type == "definition" then
		if callbacks.on_definition then
			resolve_kind(choice.def, function(resolved_def)
				callbacks.on_definition(choice.target, resolved_def, state)
			end)
		end
	end
end

---@param opts wiremux.action.RunOpts
---@param callbacks wiremux.action.Callbacks
function M.run(opts, callbacks)
	local backend = require("wiremux.backend.tmux")
	local resolver = require("wiremux.core.resolver")
	local config = require("wiremux.config")
	local picker = require("wiremux.picker")
	local notify = require("wiremux.utils.notify")

	local state = backend.state.get()

	local result = resolver.resolve(state, config.opts.targets.definitions, {
		behavior = opts.behavior,
		mode = opts.mode,
		filter = opts.filter,
	})

	if result.kind == "pick" then
		local available_items = filter_items_by_callbacks(result.items, callbacks)
		if #available_items == 0 then
			notify.warn("No targets available. Create one with :Wiremux create")
			return
		end

		picker.select(available_items, {
			prompt = opts.prompt,
			format_item = function(item)
				return item.label
			end,
		}, function(choice)
			if choice then
				dispatch_choice(choice, callbacks, state)
			end
		end)
		return
	end

	if result.targets and callbacks.on_targets then
		callbacks.on_targets(result.targets, state)
	end
end

return M
