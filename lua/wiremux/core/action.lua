local M = {}

---@class wiremux.action.RunOpts
---@field prompt string
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode

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

	-- Defer to let fzf-lua fully tear down its terminal buffer before opening the next picker
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

---@param choice wiremux.ResolveItem
---@param state wiremux.State
---@param on_resolved fun(instance: wiremux.Instance?)
local function resolve_choice(choice, state, on_resolved)
	if choice.type == "instance" then
		on_resolved(choice.instance)
		return
	end

	if choice.type == "definition" then
		resolve_kind(choice.def, function(resolved_def)
			local backend = require("wiremux.backend.tmux")
			local notify = require("wiremux.utils.notify")

			local instance = backend.create(choice.target, resolved_def, state)
			if not instance then
				notify.error(string.format("failed to create target: %s", choice.target))
			end
			on_resolved(instance)
		end)
		return
	end

	on_resolved(nil)
end

---@param opts wiremux.action.RunOpts
---@param execute fun(targets: wiremux.Instance[], state: wiremux.State)
function M.run(opts, execute)
	local backend = require("wiremux.backend.tmux")
	local resolver = require("wiremux.core.resolver")
	local config = require("wiremux.config")
	local picker = require("wiremux.picker")
	local notify = require("wiremux.utils.notify")

	local state = backend.state.get()

	local result = resolver.resolve(state, config.opts.targets.definitions, {
		behavior = opts.behavior,
		mode = opts.mode,
	})

	if result.kind == "pick" and #result.items == 0 then
		notify.warn("no targets available")
		return
	end

	if result.kind == "pick" then
		picker.select(result.items, {
			prompt = opts.prompt,
			format_item = function(item)
				return item.label
			end,
		}, function(choice)
			if not choice then
				return
			end

			resolve_choice(choice, state, function(target)
				if not target then
					notify.warn("failed to resolve target")
					return
				end

				execute({ target }, state)
			end)
		end)
		return
	end

	execute(result.targets, state)
end

return M
