local M = {}

---@class wiremux.action.RunOpts
---@field prompt string
---@field behavior wiremux.action.Behavior
---@field mode? wiremux.ResolveMode

---@param choice wiremux.ResolveItem
---@param state wiremux.State
---@return wiremux.Instance?
local function resolve_choice(choice, state)
	if choice.type == "instance" then
		return choice.instance
	end

	if choice.type == "definition" then
		local backend = require("wiremux.backend.tmux")
		local notify = require("wiremux.utils.notify")

		local instance = backend.create(choice.target, choice.def, state)
		if not instance then
			notify.error(string.format("failed to create target: %s", choice.target))
		end
		return instance
	end

	return nil
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

			local target = resolve_choice(choice, state)
			if not target then
				notify.warn("failed to resolve target")
				return
			end

			execute({ target }, state)
		end)
		return
	end

	execute(result.targets, state)
end

return M
