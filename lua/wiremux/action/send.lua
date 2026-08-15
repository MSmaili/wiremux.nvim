local M = {}
local context = require("wiremux.context")
local notify = require("wiremux.utils.notify")
local validate = require("wiremux.utils.validate")

---@class wiremux.action.SendItem
---@field value string The text/command to send
---@field label? string Display name in picker (optional, defaults to value)
---@field submit? boolean Auto-submit after sending (default: false)
---@field compose? boolean|wiremux.config.ComposeOptions Open compose buffer before sending (default: false)
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

---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
---@return wiremux.config.ComposeSessionConfig? config
---@return wiremux.validate.Error[] errors
local function resolve_compose(item, opts)
	local config = require("wiremux.config").opts
	local defaults = config.actions.send or {}
	local selected
	local path
	if item.compose ~= nil then
		selected = item.compose
		path = "item.compose"
	elseif opts.compose ~= nil then
		selected = opts.compose
		path = "opts.compose"
	else
		selected = defaults.compose
		path = "actions.send.compose"
	end
	return validate.resolve_compose(config.ui.compose, selected, path)
end

---@param errors wiremux.validate.Error[]
local function warn_validation_errors(errors)
	for _, err in ipairs(errors) do
		notify.warn(err.message)
	end
end

---@class wiremux.action.PreparedCandidate
---@field item wiremux.action.SendItem
---@field placeholder_capture? wiremux.context.PlaceholderCapture
---@field compose_config? wiremux.config.ComposeSessionConfig

---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
---@return wiremux.action.PreparedCandidate?
local function prepare_candidate(item, opts)
	if type(item.value) ~= "string" then
		notify.warn("wiremux.send item.value must be a string")
		return nil
	end

	local compose_config, errors = resolve_compose(item, opts)
	if #errors > 0 then
		warn_validation_errors(errors)
		return nil
	end

	local capture_names
	if compose_config then
		capture_names = require("wiremux.config").opts.ui.compose.capture_placeholders
	end
	local reopening = item.value == ""
		and compose_config ~= nil
		and require("wiremux.ui.compose").get_buf() ~= nil
	local capture = not reopening and context.capture(item.value, capture_names) or nil

	return {
		item = item,
		placeholder_capture = capture,
		compose_config = compose_config,
	}
end

---Build picker items from send library.
---@param items wiremux.action.SendItem[]
---@param opts wiremux.config.ActionConfig
---@return table[] picker_items
local function prepare_picker_items(items, opts)
	local picker_items = {}

	for _, item in ipairs(items) do
		if is_visible(item) then
			local prepared = prepare_candidate(item, opts)
			if prepared then
				table.insert(picker_items, {
					label = item.label or item.value,
					value = item,
					placeholder_capture = prepared.placeholder_capture,
					compose_config = prepared.compose_config,
				})
			end
		end
	end

	return picker_items
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
	local focus = first_non_nil(opts.focus, defaults.focus)

	if submit then
		post_keys = append_submit(post_keys)
	end

	return {
		focus = focus,
		pre_keys = pre_keys,
		post_keys = post_keys,
	}
end

---@param text string
---@param capture wiremux.context.PlaceholderCapture
---@return string?
local function materialize_with_context(text, capture)
	local ok, materialized = pcall(function()
		local extended = context.extend(capture, text)
		return context.materialize(text, extended)
	end)
	if not ok then
		notify.error(materialized)
		return nil
	end
	return materialized
end

---@param pages wiremux.ui.ComposePage[]
---@return string?
local function prepare_compose_pages(pages)
	local materialized_pages = {}
	for index, page in ipairs(pages) do
		local capture = type(page.meta) == "table" and page.meta.placeholder_capture or nil
		local ok, materialized = pcall(function()
			local extended = context.extend(capture, page.text)
			return context.materialize(page.text, extended)
		end)
		if not ok then
			notify.error(string.format("Failed to prepare compose page %d: %s", index, tostring(materialized)))
			return nil
		end
		materialized_pages[index] = materialized:gsub("%s+$", "")
	end
	return table.concat(materialized_pages, "\n\n")
end

---Resolve all options against defaults, then send
---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
---@param placeholder_capture? wiremux.context.PlaceholderCapture
---@param compose_config? wiremux.config.ComposeSessionConfig
local function resolve_and_send(item, opts, placeholder_capture, compose_config)
	local defaults = require("wiremux.config").opts.actions.send or {}
	local backend_opts = resolve_send_backend_opts(item, opts, defaults)

	local resolved = {
		focus = backend_opts.focus,
		pre_keys = backend_opts.pre_keys,
		post_keys = backend_opts.post_keys,
		behavior = first_non_nil(opts.behavior, defaults.behavior, "pick"),
		mode = first_non_nil(opts.mode, "auto"),
		filter = opts.filter,
		target = opts.target,
	}

	if compose_config then
		require("wiremux.ui.compose").open(item.value, {
			config = compose_config,
			page_meta = { placeholder_capture = placeholder_capture },
			on_confirm = function(pages)
				local materialized = prepare_compose_pages(pages)
				if materialized == nil then
					return false
				end
				vim.schedule(function()
					do_send(materialized, resolved, item.title)
				end)
				return true
			end,
		})
		return
	end

	assert(placeholder_capture, "wiremux direct send requires a placeholder capture")
	local materialized = materialize_with_context(item.value, placeholder_capture)
	if not materialized then
		return
	end

	do_send(materialized, resolved, item.title)
end

---Send a single send item
---@param item wiremux.action.SendItem
---@param opts wiremux.config.ActionConfig
local function send_single_item(item, opts)
	local prepared = prepare_candidate(item, opts)
	if not prepared then
		return
	end

	resolve_and_send(
		prepared.item,
		opts,
		prepared.placeholder_capture,
		prepared.compose_config
	)
end

---Send from send library (picker)
---@param items wiremux.action.SendItem[]
---@param opts wiremux.config.ActionConfig
local function send_from_library(items, opts)
	-- Capture before picker opens (visual selection is lost when picker opens)
	local picker_items = prepare_picker_items(items, opts)

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
		resolve_and_send(item, opts, choice.placeholder_capture, choice.compose_config)
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
