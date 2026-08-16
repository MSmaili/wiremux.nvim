local M = {}
local context = require("wiremux.context")
local notify = require("wiremux.utils.notify")
local request_builder = require("wiremux.action.send.request")

---@class wiremux.action.SendItem
---@field value string The text/command to send
---@field label? string Display name in picker (optional, defaults to value)
---@field submit? boolean Auto-submit after sending (default: false)
---@field compose? boolean|wiremux.config.ComposeOptions Open compose buffer before sending (default: false)
---@field placeholders? boolean Expand placeholders (default: true). Set false for literal source text.
---@field visible? boolean|fun(): boolean Show this item in picker (default: true)
---@field title? string Custom tmux window / zellij tab name when creating
---@field pre_keys? string|string[] Keystrokes to send before pasting (e.g. {"C-c"}, {"i"})
---@field post_keys? string|string[] Keystrokes to send after pasting (e.g. {"Escape"})

---Check if item should be visible.
---@param item wiremux.action.SendItem
---@return boolean
local function is_visible(item)
	if type(item) ~= "table" then
		return true
	end
	local visible = item.visible
	if visible == nil then
		return true
	end
	if type(visible) == "boolean" then
		return visible
	end
	if type(visible) ~= "function" then
		notify.warn("wiremux.send item.visible must be a boolean or function")
		return false
	end

	local ok, result = pcall(visible)
	if not ok then
		notify.warn(string.format("Error in visible(): %s", result))
		return false
	end
	return result == true
end

---@param errors wiremux.action.SendPreparationError[]
local function warn_preparation_errors(errors)
	for _, err in ipairs(errors) do
		notify.warn(err.message)
	end
end

---Execute the send action with fully prepared delivery options.
---@param payload string
---@param delivery wiremux.action.DeliveryOptions
---@param title? string
local function do_send(payload, delivery, title)
	local action = require("wiremux.core.action")
	local backend = require("wiremux.backend").get()
	if not backend then
		return
	end

	local backend_send_opts = {
		focus = delivery.focus,
		pre_keys = delivery.pre_keys,
		post_keys = delivery.post_keys,
	}

	action.run({
		prompt = "Send to",
		behavior = delivery.behavior,
		mode = delivery.mode,
		filter = delivery.filter,
		target = delivery.target,
	}, {
		on_targets = function(targets, state)
			backend.send(payload, targets, backend_send_opts, state)
		end,
		on_definition = function(name, def, state)
			local has_own_cmd = def.cmd ~= nil
			local modified_def = vim.tbl_extend("force", {}, def, {
				cmd = def.cmd or payload,
				title = title,
			})
			local inst = backend.create(name, modified_def, state)
			if inst and has_own_cmd then
				backend.wait_for_ready(inst, { timeout_ms = def.startup_timeout }, function()
					backend.send(payload, { inst }, backend_send_opts, state)
				end)
			end
		end,
	})
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
		local ok, materialized = pcall(function()
			assert(type(page.capture) == "table", "wiremux compose page capture must be a table")
			local placeholder_capture = page.capture.placeholder_capture
			local extended = context.extend(placeholder_capture, page.text)
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

---@param request wiremux.action.PreparedSendRequest
local function execute_request(request)
	if request.compose then
		require("wiremux.ui.compose").open(request.raw_text, {
			config = request.compose.config,
			capture = { placeholder_capture = request.placeholder_capture },
			on_confirm = function(pages)
				local materialized = prepare_compose_pages(pages)
				if materialized == nil then
					return false
				end
				vim.schedule(function()
					do_send(materialized, request.delivery, request.target_title)
				end)
				return true
			end,
		})
		return
	end

	local materialized = materialize_with_context(request.raw_text, request.placeholder_capture)
	if materialized == nil then
		return
	end
	do_send(materialized, request.delivery, request.target_title)
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
local function send_single_item(item, preparation)
	local request, errors = request_builder.prepare(item, preparation)
	if not request then
		warn_preparation_errors(errors)
		return
	end
	execute_request(request)
end

---@param items wiremux.action.SendItem[]
---@param preparation wiremux.action.SendPreparationContext
local function send_from_library(items, preparation)
	local picker_items = {}
	for _, item in ipairs(items) do
		if is_visible(item) then
			local request, errors = request_builder.prepare(item, preparation)
			if request then
				table.insert(picker_items, {
					label = request.label,
					value = request,
				})
			else
				warn_preparation_errors(errors)
			end
		end
	end

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
		if choice then
			execute_request(choice.value)
		end
	end)
end

---@return boolean reopened
local function reopen_existing_compose()
	local compose = require("wiremux.ui.compose")
	if compose.get_buf() == nil then
		return false
	end
	compose.open("")
	return true
end

---Send text or item(s) to target.
---@overload fun(text?: string, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem, opts?: wiremux.config.ActionConfig)
---@overload fun(text: wiremux.action.SendItem[], opts?: wiremux.config.ActionConfig)
---@param text? string|wiremux.action.SendItem|wiremux.action.SendItem[]
---@param opts? wiremux.config.ActionConfig
function M.send(text, opts)
	if (text == nil or text == "") and reopen_existing_compose() then
		return
	end

	local config = require("wiremux.config").get()
	local preparation, errors = request_builder.snapshot(opts, config)
	if not preparation then
		warn_preparation_errors(errors)
		return
	end

	if text == nil or text == "" then
		return send_single_item({ value = "", compose = true }, preparation)
	end
	if type(text) == "table" and vim.islist(text) then
		return send_from_library(text, preparation)
	end
	if type(text) == "table" then
		return send_single_item(text, preparation)
	end
	if type(text) == "string" then
		return send_single_item({ value = text }, preparation)
	end

	warn_preparation_errors({ {
		code = "invalid_item",
		path = "text",
		message = "wiremux.send text must be a string, item, or list of items",
	} })
end

return M
