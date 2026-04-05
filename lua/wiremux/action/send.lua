local M = {}
local notify = require("wiremux.utils.notify")

---@class wiremux.action.SendItem
---@field value string The text/command to send
---@field label? string Display name in picker (optional, defaults to value)
---@field submit? boolean Auto-submit after sending (default: false)
---@field compose? boolean Open compose buffer before sending (default: false)
---@field visible? boolean|fun(): boolean Show this item in picker (default: true)
---@field title? string Custom tmux window / zellij tab name when creating
---@field pre_keys? string|string[] Keystrokes to send before pasting (e.g. {"C-c"}, {"i"})
---@field post_keys? string|string[] Keystrokes to send after pasting (e.g. {"Escape"})

---@generic T
---@param first T?
---@param second T?
---@param third T?
---@return T?
local function first_non_nil(first, second, third)
	if first ~= nil then
		return first
	end
	if second ~= nil then
		return second
	end
	return third
end

---@param post_keys? string|string[]
---@return string[]
local function append_submit(post_keys)
	local keys = type(post_keys) == "table" and { unpack(post_keys) } or (post_keys and { post_keys } or {})
	table.insert(keys, "Enter")
	return keys
end

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

	local ok, result = pcall(visible)
	if not ok then
		notify.warn(string.format("Error in visible(): %s", result))
		return false
	end
	return result == true
end

---Build picker items from send library
---@param items wiremux.action.SendItem[]
---@return table[] picker_items
---@return table<string, string> frozen_context
local function prepare_picker_items(items)
	local picker_items = {}
	local visible_texts = {}

	for _, item in ipairs(items) do
		if is_visible(item) then
			table.insert(visible_texts, item.value)
			table.insert(picker_items, {
				label = item.label or item.value,
				value = item,
			})
		end
	end

	return picker_items, require("wiremux.context").snapshot(visible_texts)
end

---Execute the send action with fully resolved options
---@param expanded string The text with placeholders expanded
---@param opts table Fully resolved action options
---@param title? string Custom tmux window / zellij tab name when creating
local function do_send(expanded, opts, title)
	local action = require("wiremux.core.action")
	local backend = require("wiremux.backend").get()

	if not backend then
		return
	end

	local backend_send_opts = {
		focus = opts.focus,
		pre_keys = opts.pre_keys,
		post_keys = opts.post_keys,
	}

	action.run({
		prompt = "Send to",
		behavior = opts.behavior,
		mode = opts.mode,
		filter = opts.filter,
		target = opts.target,
	}, {
		on_targets = function(targets, state)
			backend.send(expanded, targets, backend_send_opts, state)
		end,
		on_definition = function(name, def, state)
			local has_own_cmd = def.cmd ~= nil
			local modified_def = vim.tbl_extend("force", {}, def, {
				cmd = def.cmd or expanded,
				title = title,
			})
			local inst = backend.create(name, modified_def, state)
			if inst and has_own_cmd then
				backend.wait_for_ready(inst, { timeout_ms = def.startup_timeout }, function()
					backend.send(expanded, { inst }, backend_send_opts, state)
				end)
			end
		end,
	})
end

---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
---@param defaults wiremux.config.ActionConfig
---@return { focus: boolean?, pre_keys: string|string[]?, post_keys: string|string[]? }
local function resolve_send_backend_opts(item, opts, defaults)
	local submit = first_non_nil(item.submit, opts.submit, defaults.submit)
	local pre_keys = first_non_nil(item.pre_keys, opts.pre_keys, defaults.pre_keys)
	local post_keys = first_non_nil(item.post_keys, opts.post_keys, defaults.post_keys)

	if submit then
		post_keys = append_submit(post_keys)
	end

	return {
		focus = first_non_nil(opts.focus, defaults.focus),
		pre_keys = pre_keys,
		post_keys = post_keys,
	}
end

---@param text string
---@param frozen_context table<string, string>
---@return string?
local function expand_with_context(text, frozen_context)
	local ok, expanded = pcall(require("wiremux.context").expand, text, frozen_context)
	if not ok then
		notify.error(expanded)
		return nil
	end
	return expanded
end

---Resolve all options against defaults, then send
---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
---@param frozen_context table<string, string>
local function resolve_and_send(item, opts, frozen_context)
	if type(item.value) ~= "string" then
		notify.warn("wiremux.send item.value must be a string")
		return
	end

	local defaults = require("wiremux.config").opts.actions.send or {}
	local backend_opts = resolve_send_backend_opts(item, opts, defaults)
	local resolved = {
		focus = backend_opts.focus,
		pre_keys = backend_opts.pre_keys,
		post_keys = backend_opts.post_keys,
		behavior = opts.behavior or defaults.behavior or "pick",
		mode = opts.mode or "auto",
		filter = opts.filter,
		target = opts.target,
	}

	if first_non_nil(item.compose, opts.compose, defaults.compose) then
		require("wiremux.ui.compose").open(item.value, function(edited_text)
			local expanded = expand_with_context(edited_text, frozen_context)
			if expanded then
				do_send(expanded, resolved, item.title)
			end
		end)
		return
	end

	local expanded = expand_with_context(item.value, frozen_context)
	if not expanded then
		return
	end

	do_send(expanded, resolved, item.title)
end

---Send a single send item
---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
local function send_single_item(item, opts)
	resolve_and_send(item, opts, require("wiremux.context").snapshot(item.value))
end

---Send from send library (picker)
---@param items wiremux.action.SendItem[]
---@param opts wiremux.config.ActionConfig
local function send_from_library(items, opts)
	-- Capture before picker opens (visual selection is lost when picker opens)
	local picker_items, frozen_context = prepare_picker_items(items)

	if #picker_items == 0 then
		notify.warn("No items available")
		return
	end

	require("wiremux.picker").select(picker_items, {
		prompt = "Select item",
		format_item = function(picker_item)
			return picker_item.label
		end,
	}, function(choice)
		if not choice then
			return
		end

		---@type wiremux.action.SendItem
		local item = choice.value
		resolve_and_send(item, opts, frozen_context)
	end)
end

---Send text or item(s) to target
---@overload fun(text: string, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem[], opts?: wiremux.config.ActionConfig)
---@param text string|wiremux.action.SendItem|wiremux.action.SendItem[]
---@param opts? wiremux.config.ActionConfig
function M.send(text, opts)
	opts = opts or {}

	if not require("wiremux.backend").get() then
		return
	end

	if not text or text == "" then
		return send_single_item({ value = "", compose = true }, opts)
	end

	if type(text) == "table" and vim.islist(text) then
		return send_from_library(text, opts)
	end

	if type(text) == "table" then
		return send_single_item(text, opts)
	end

	return send_single_item({ value = text }, opts)
end

return M
