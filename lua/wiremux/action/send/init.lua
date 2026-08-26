local M = {}
local context = require("wiremux.context")
local delivery = require("wiremux.action.send.delivery")
local notify = require("wiremux.utils.notify")
local request_builder = require("wiremux.action.send.request")

---@class wiremux.action.SendItem
---@field value string The text/command to send
---@field label? string Display name in picker (optional, defaults to value)
---@field submit? boolean Auto-submit after sending (default: false)
---@field compose? boolean|wiremux.config.ComposeOptions Open compose buffer before sending (default: false)
---@field placeholders? boolean Materialize placeholders (default: true). Set false to preserve placeholder-shaped source text literally.
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
	if visible == nil or type(visible) == "boolean" then
		return visible ~= false
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

---@param errors wiremux.Error[]
local function warn_errors(errors)
	for _, err in ipairs(errors) do
		notify.warn(err.message)
	end
end

---@param payload string
---@param options wiremux.action.SendOptions
---@param target_title? string
local function deliver_payload(payload, options, target_title)
	local started, err = delivery.send(payload, options, target_title)
	if not started then
		notify.error(err)
	end
end

---Join ordered compose pages into one payload, resolving each against its own source.
---@param pages wiremux.ui.ComposePage[]
---@return string? payload
---@return string? error
local function compose_payload(pages)
	if type(pages) ~= "table" or not vim.islist(pages) then
		return nil, "Failed to prepare compose payload: pages must be a list"
	end

	local payloads = {}
	for index, page in ipairs(pages) do
		local source = type(page) == "table" and type(page.text) == "string" and page.source or nil
		if type(source) ~= "table" then
			return nil, string.format("Failed to prepare compose page %d: malformed page", index)
		end
		local text = source.resolve and context.resolve(page.text, source.origin) or page.text
		payloads[index] = text:gsub("%s+$", "")
	end
	return table.concat(payloads, "\n\n"), nil
end

---@param source wiremux.context.Source
---@param name string
---@return string? text
---@return string? syntax
local function preview_placeholder(source, name)
	if not source.resolve then
		return "Placeholder replacement is disabled for this page.", "text"
	end
	local value = context.get(name, source.origin)
	if value == nil then
		return string.format("No value is available for {%s}.", name), "text"
	end
	return value == "" and "(empty)" or value, name == "changes" and "diff" or "text"
end

---@param request wiremux.action.PreparedSendRequest
local function execute_request(request)
	local delivery_options = request.delivery
	local target_title = request.target_title
	local source = request.source
	if request.compose then
		require("wiremux.ui.compose").open(request.raw_text, {
			config = request.compose,
			source = source,
			on_preview = preview_placeholder,
			on_confirm = function(pages)
				local payload, err = compose_payload(pages)
				if payload == nil then
					notify.error(err)
					return false
				end
				vim.schedule(function()
					deliver_payload(payload, delivery_options, target_title)
				end)
				return true
			end,
		})
		return
	end

	local payload = source.resolve and context.resolve(request.raw_text, source.origin) or request.raw_text
	deliver_payload(payload, delivery_options, target_title)
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
local function send_single_item(item, preparation)
	local request, errors = request_builder.prepare(item, preparation)
	if not request then
		warn_errors(errors)
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
				warn_errors(errors)
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
	local preparation, errors = request_builder.prepare_context(opts, config)
	if not preparation then
		warn_errors(errors)
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

	notify.warn("wiremux.send text must be a string, item, or list of items")
end

return M
