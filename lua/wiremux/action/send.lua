local M = {}

---@class wiremux.action.SendItem
---@field name string Display name for the item
---@field text string Text to send when selected

---Send text or pick from items to send to targets
---@param text string|wiremux.action.SendItem[]
---@param opts? wiremux.config.ActionConfig
function M.send(text, opts)
	opts = opts or {}

	if type(text) == "table" then
		return M._pick_items(text, opts)
	end

	local config = require("wiremux.config")
	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end
	local context = require("wiremux.context")
	local action = require("wiremux.core.action")
	local notify = require("wiremux.utils.notify")

	local ok, expanded = pcall(context.expand, text)
	if not ok then
		notify.error(expanded)
		return
	end

	local focus = opts.focus or config.opts.actions.send.focus

	action.run({
		prompt = "Send to",
		behavior = opts.behavior or config.opts.actions.send.behavior or "pick",
	}, function(targets, state)
		backend.send(expanded, targets, { focus = focus }, state)
	end)
end

---@param items wiremux.action.SendItem[]
---@param opts wiremux.config.ActionConfig
function M._pick_items(items, opts)
	local picker = require("wiremux.picker")

	picker.select(items, {
		prompt = "Select item",
		format_item = function(item)
			return item.name
		end,
	}, function(choice)
		if choice then
			M.send(choice.text, opts)
		end
	end)
end

return M
