local M = {}

---@class wiremux.action.SendItem
---@field value string The text/command to send
---@field label? string Display name in picker (optional, defaults to value)
---@field submit? boolean Auto-submit after sending (default: false)
---@field visible? boolean|fun(): boolean Show this item in picker (default: true)

---Check if item should be visible
---@param item wiremux.action.SendItem
---@return boolean
local function is_visible(item)
	local visible = item.visible

	if visible == nil then
		return true
	end

	if type(visible) == "boolean" then
		return visible
	end

	-- Function
	local ok, result = pcall(visible)
	if not ok then
		require("wiremux.utils.notify").warn(string.format("Error in visible(): %s", result))
		return false
	end
	return result == true
end

---Build picker items from send library
---@param items wiremux.action.SendItem[]
---@return table[] Picker items
local function build_picker_items(items)
	local picker_items = {}

	for _, item in ipairs(items) do
		if is_visible(item) then
			local label = item.label or item.value

			table.insert(picker_items, {
				label = label,
				value = item,
			})
		end
	end

	return picker_items
end

---Execute the send action with expanded text
---@param expanded string The text with placeholders expanded
---@param opts wiremux.config.ActionConfig
---@param submit boolean Whether to auto-submit
local function do_send(expanded, opts, submit)
	local config = require("wiremux.config")
	local action = require("wiremux.core.action")
	local backend = require("wiremux.backend").get()

	if not backend then
		return
	end

	local focus = opts.focus or config.opts.actions.send.focus

	action.run({
		prompt = "Send to",
		behavior = opts.behavior or config.opts.actions.send.behavior or "pick",
		filter = opts.filter,
	}, {
		on_targets = function(targets, state)
			backend.send(expanded, targets, { focus = focus, submit = submit }, state)
		end,
		on_definition = function(name, def, state)
			local modified_def = def.cmd and def or vim.tbl_extend("force", def, { cmd = expanded })
			local inst = backend.create(name, modified_def, state)
			if inst and def.cmd then
				backend.send(expanded, { inst }, { focus = focus, submit = submit }, state)
			end
		end,
	})
end

---Send from send library (picker)
---@param items wiremux.action.SendItem[]
---@param opts wiremux.config.ActionConfig
function M._send_from_library(items, opts)
	local picker_items = build_picker_items(items)

	if #picker_items == 0 then
		require("wiremux.utils.notify").warn("No items available")
		return
	end

	local picker = require("wiremux.picker")

	picker.select(picker_items, {
		prompt = "Select item",
		format_item = function(picker_item)
			return picker_item.label
		end,
	}, function(choice)
		if not choice then
			return
		end

		M._send_single_item(choice.value, opts)
	end)
end

---Send a single send item
---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
function M._send_single_item(item, opts)
	local context = require("wiremux.context")
	local config = require("wiremux.config")

	local ok, expanded = pcall(context.expand, item.value)
	if not ok then
		require("wiremux.utils.notify").error(expanded)
		return
	end

	local submit = item.submit
	if submit == nil then
		submit = opts.submit or config.opts.actions.send.submit
	end

	do_send(expanded, opts, submit)
end

---Send text or item(s) to target
---@overload fun(text: string, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem[], opts?: wiremux.config.ActionConfig)
---@param text string|wiremux.action.SendItem|wiremux.action.SendItem[]
---@param opts? wiremux.config.ActionConfig
function M.send(text, opts)
	opts = opts or {}

	if type(text) == "table" and vim.islist(text) then
		return M._send_from_library(text, opts)
	end

	if type(text) == "table" then
		return M._send_single_item(text, opts)
	end

	local context = require("wiremux.context")
	local config = require("wiremux.config")

	local ok, expanded = pcall(context.expand, text)
	if not ok then
		require("wiremux.utils.notify").error(expanded)
		return
	end

	local submit = opts.submit or config.opts.actions.send.submit
	do_send(expanded, opts, submit)
end

return M
