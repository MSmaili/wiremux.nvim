local M = {}
local delivery = require("wiremux.action.send.delivery")
local materialize = require("wiremux.action.send.materialize")
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

---@param payload string
---@param request wiremux.action.PreparedSendRequest
local function deliver_payload(payload, request)
	local started, err = delivery.send(payload, request.delivery, request.target_title)
	if not started then
		assert(err ~= nil, "wiremux delivery failure requires an error")
		notify.error(err.message)
	end
end

---@param request wiremux.action.PreparedSendRequest
local function execute_request(request)
	if request.compose then
		local confirmed = false
		require("wiremux.ui.compose").open(request.raw_text, {
			config = request.compose.config,
			capture = { placeholder_capture = request.placeholder_capture },
			on_confirm = function(pages)
				if confirmed then
					return true
				end
				local payload, err = materialize.compose(pages)
				if payload == nil then
					assert(err ~= nil, "wiremux compose materialization failure requires an error")
					notify.error(err.message)
					return false
				end
				confirmed = true
				vim.schedule(function()
					deliver_payload(payload, request)
				end)
				return true
			end,
		})
		return
	end

	local payload, err = materialize.direct(request)
	if payload == nil then
		assert(err ~= nil, "wiremux direct materialization failure requires an error")
		notify.error(err.message)
		return
	end
	deliver_payload(payload, request)
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

	local selected = false
	require("wiremux.picker").select(picker_items, {
		prompt = "Select item",
		format_item = function(picker_item)
			return picker_item.label
		end,
	}, function(choice)
		if selected then
			return
		end
		selected = true
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
