local M = {}

local context = require("wiremux.context")
local placeholder = require("wiremux.placeholder")
local validate = require("wiremux.utils.validate")

---@alias wiremux.action.SendMode "auto"|"instances"|"definitions"|"all"

---@class wiremux.action.DeliveryOptions Immutable-by-ownership options consumed only by target selection and delivery.
---@field focus? boolean
---@field behavior wiremux.action.Behavior
---@field mode wiremux.action.SendMode
---@field target? string
---@field filter? wiremux.config.FilterConfig
---@field pre_keys? string|string[]
---@field post_keys? string|string[]

---@class wiremux.action.PreparedSendRequest Complete execution input fixed before picker or compose interaction.
---@field raw_text string Raw template text; never overwritten with a materialized payload.
---@field label string
---@field placeholder_capture wiremux.context.PlaceholderCapture Point-in-time capture owned by this request and transferred to its compose page when applicable.
---@field compose? { config: wiremux.config.ComposeSessionConfig }
---@field delivery wiremux.action.DeliveryOptions
---@field target_title? string Target creation title, separate from the compose window title.

---@alias wiremux.action.SendPreparationErrorCode "invalid_config"|"invalid_item"|"invalid_option"|"invalid_compose"|"capture_failed"

---@class wiremux.action.SendPreparationError
---@field code wiremux.action.SendPreparationErrorCode
---@field path string
---@field message string

---@class wiremux.action.SendPreparationContext
---@field defaults table
---@field call table
---@field global_compose wiremux.config.ComposeUIConfig
---@field capture_placeholders string[]

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

---@param value any
---@return any
local function copy_mutable(value)
	if type(value) == "table" then
		return vim.deepcopy(value)
	end
	return value
end

---@param value any
---@return wiremux.config.FilterConfig|any
local function copy_filter(value)
	if type(value) ~= "table" then
		return value
	end
	return {
		instances = value.instances,
		definitions = value.definitions,
	}
end

---@param options any
---@return table
local function copy_action_options(options)
	options = type(options) == "table" and options or {}
	return {
		behavior = options.behavior,
		focus = options.focus,
		submit = options.submit,
		compose = copy_mutable(options.compose),
		mode = options.mode,
		target = options.target,
		filter = copy_filter(options.filter),
		pre_keys = copy_mutable(options.pre_keys),
		post_keys = copy_mutable(options.post_keys),
	}
end

---@param code wiremux.action.SendPreparationErrorCode
---@param path string
---@param message string
---@return wiremux.action.SendPreparationError
local function preparation_error(code, path, message)
	return { code = code, path = path, message = message }
end

---@param errors wiremux.action.SendPreparationError[]
---@param err? wiremux.action.SendPreparationError
local function collect_error(errors, err)
	if err ~= nil then
		errors[#errors + 1] = err
	end
end

---@param errors wiremux.validate.Error[]
---@return wiremux.action.SendPreparationError[]
local function compose_errors(errors)
	local result = {}
	for _, err in ipairs(errors) do
		table.insert(result, preparation_error("invalid_compose", err.path, err.message))
	end
	return result
end

---@param value any
---@return boolean
local function valid_keys(value)
	if value == nil or type(value) == "string" then
		return true
	end
	if type(value) ~= "table" or not vim.islist(value) then
		return false
	end
	for _, key in ipairs(value) do
		if type(key) ~= "string" then
			return false
		end
	end
	return true
end

---@param value any
---@return boolean
local function valid_filter(value)
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	return (value.instances == nil or type(value.instances) == "function")
		and (value.definitions == nil or type(value.definitions) == "function")
end

---@param value any
---@return string|string[]|any
local function copy_keys(value)
	return copy_mutable(value)
end

---@param post_keys? string|string[]
---@return string[]
local function append_submit(post_keys)
	local result
	if type(post_keys) == "table" then
		result = vim.list_slice(post_keys)
	elseif post_keys ~= nil then
		result = { post_keys }
	else
		result = {}
	end
	table.insert(result, "Enter")
	return result
end

---@param capture any
---@return boolean
local function valid_capture(capture)
	if type(capture) ~= "table"
		or type(capture.enabled) ~= "boolean"
		or type(capture.capture_set) ~= "table"
		or type(capture.values) ~= "table"
	then
		return false
	end
	for name, attempted in pairs(capture.capture_set) do
		if not placeholder.is_valid_name(name) or attempted ~= true then
			return false
		end
	end
	for name, value in pairs(capture.values) do
		if not placeholder.is_valid_name(name) or capture.capture_set[name] ~= true or type(value) ~= "string" then
			return false
		end
	end
	return true
end

---Snapshot call-level and global send configuration once for a public send invocation.
---@param opts? wiremux.config.ActionConfig
---@param config wiremux.config.UserOptions
---@return wiremux.action.SendPreparationContext? context
---@return wiremux.action.SendPreparationError[] errors
function M.snapshot(opts, config)
	if opts ~= nil and type(opts) ~= "table" then
		return nil, {
			preparation_error("invalid_option", "opts", "wiremux.send opts must be a table"),
		}
	end
	if type(config) ~= "table" then
		return nil, {
			preparation_error("invalid_config", "config", "wiremux send configuration must be a table"),
		}
	end

	local global_compose = vim.tbl_get(config, "ui", "compose")
	if type(global_compose) ~= "table" then
		return nil, {
			preparation_error("invalid_config", "ui.compose", "ui.compose must be a table"),
		}
	end

	local listed, resolver_names = pcall(context.list)
	if not listed or type(resolver_names) ~= "table" then
		return nil, {
			preparation_error("invalid_config", "context.resolvers", "Unable to read configured placeholder resolvers"),
		}
	end
	local known_placeholders = {}
	for _, name in ipairs(resolver_names) do
		known_placeholders[name] = true
	end
	local capture_names, capture_errors = validate.capture_names(
		global_compose.capture_placeholders,
		"ui.compose.capture_placeholders",
		known_placeholders
	)
	if #capture_errors > 0 then
		local errors = {}
		for _, err in ipairs(capture_errors) do
			table.insert(errors, preparation_error("invalid_config", err.path, err.message))
		end
		return nil, errors
	end

	return {
		defaults = copy_action_options(vim.tbl_get(config, "actions", "send")),
		call = copy_action_options(opts),
		global_compose = vim.deepcopy(global_compose),
		capture_placeholders = capture_names or {},
	}, {}
end

---@param path string
---@param value any
---@return wiremux.action.SendPreparationError?
local function validate_keys(path, value)
	if valid_keys(value) then
		return nil
	end
	return preparation_error("invalid_option", path, path .. " must be a string or list of strings")
end

---@param item any
---@return wiremux.action.SendPreparationError[] errors
local function validate_item(item)
	if type(item) ~= "table" then
		return {
			preparation_error("invalid_item", "item", "wiremux.send item must be a table"),
		}
	end
	if type(item.value) ~= "string" then
		return {
			preparation_error("invalid_item", "item.value", "wiremux.send item.value must be a string"),
		}
	end
	if item.label ~= nil and type(item.label) ~= "string" then
		return {
			preparation_error("invalid_item", "item.label", "wiremux.send item.label must be a string"),
		}
	end
	if item.title ~= nil and type(item.title) ~= "string" then
		return {
			preparation_error("invalid_item", "item.title", "wiremux.send item.title must be a string"),
		}
	end
	if item.placeholders ~= nil and type(item.placeholders) ~= "boolean" then
		return {
			preparation_error("invalid_item", "item.placeholders", "wiremux.send item.placeholders must be a boolean"),
		}
	end
	return {}
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.config.ComposeSessionConfig? config
---@return wiremux.action.SendPreparationError[] errors
local function prepare_compose(item, preparation)
	local selected
	local path
	if item.compose ~= nil then
		selected = item.compose
		path = "item.compose"
	elseif preparation.call.compose ~= nil then
		selected = preparation.call.compose
		path = "opts.compose"
	else
		selected = preparation.defaults.compose
		path = "actions.send.compose"
	end

	local config, errors = validate.resolve_compose(preparation.global_compose, selected, path)
	if #errors > 0 then
		return nil, compose_errors(errors)
	end
	return config, {}
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.action.DeliveryOptions? delivery
---@return wiremux.action.SendPreparationError[] errors
local function prepare_delivery(item, preparation)
	local submit = first_non_nil(item.submit, preparation.call.submit, preparation.defaults.submit)
	local delivery = {
		focus = first_non_nil(preparation.call.focus, preparation.defaults.focus),
		behavior = first_non_nil(preparation.call.behavior, preparation.defaults.behavior, "pick"),
		mode = first_non_nil(preparation.call.mode, preparation.defaults.mode, "auto"),
		target = first_non_nil(preparation.call.target, preparation.defaults.target),
		filter = first_non_nil(preparation.call.filter, preparation.defaults.filter),
		pre_keys = first_non_nil(item.pre_keys, preparation.call.pre_keys, preparation.defaults.pre_keys),
		post_keys = first_non_nil(item.post_keys, preparation.call.post_keys, preparation.defaults.post_keys),
	}

	local errors = {}
	if submit ~= nil and type(submit) ~= "boolean" then
		table.insert(errors, preparation_error("invalid_option", "submit", "submit must be a boolean"))
	end
	if delivery.focus ~= nil and type(delivery.focus) ~= "boolean" then
		table.insert(errors, preparation_error("invalid_option", "focus", "focus must be a boolean"))
	end
	if not ({ all = true, pick = true, last = true })[delivery.behavior] then
		table.insert(errors, preparation_error("invalid_option", "behavior", "behavior must be one of: all, last, pick"))
	end
	if not ({ auto = true, instances = true, definitions = true, all = true })[delivery.mode] then
		table.insert(errors, preparation_error("invalid_option", "mode", "mode must be one of: all, auto, definitions, instances"))
	end
	if delivery.target ~= nil and type(delivery.target) ~= "string" then
		table.insert(errors, preparation_error("invalid_option", "target", "target must be a string"))
	end
	if not valid_filter(delivery.filter) then
		table.insert(errors, preparation_error("invalid_option", "filter", "filter must contain function callbacks"))
	end
	collect_error(errors, validate_keys("pre_keys", delivery.pre_keys))
	collect_error(errors, validate_keys("post_keys", delivery.post_keys))
	if #errors > 0 then
		return nil, errors
	end

	delivery.filter = copy_filter(delivery.filter)
	delivery.pre_keys = copy_keys(delivery.pre_keys)
	delivery.post_keys = submit and append_submit(delivery.post_keys) or copy_keys(delivery.post_keys)
	return delivery, {}
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@param compose_config? wiremux.config.ComposeSessionConfig
---@return wiremux.context.PlaceholderCapture? capture
---@return wiremux.action.SendPreparationError[] errors
local function prepare_capture(item, preparation, compose_config)
	if item.placeholders == false then
		return { enabled = false, capture_set = {}, values = {} }, {}
	end

	local ok, capture = pcall(
		context.capture,
		item.value,
		compose_config and preparation.capture_placeholders or nil
	)
	if not ok then
		return nil, {
			preparation_error("capture_failed", "item.value", "Failed to capture placeholders: " .. tostring(capture)),
		}
	end
	if not valid_capture(capture) then
		return nil, {
			preparation_error("capture_failed", "item.value", "Placeholder capture returned an invalid capture"),
		}
	end
	return capture, {}
end

---@param item wiremux.action.SendItem
---@param compose_config? wiremux.config.ComposeSessionConfig
---@param delivery wiremux.action.DeliveryOptions
---@param capture wiremux.context.PlaceholderCapture
---@return wiremux.action.PreparedSendRequest
local function build_request(item, compose_config, delivery, capture)
	return {
		raw_text = item.value,
		label = item.label or item.value,
		placeholder_capture = capture,
		compose = compose_config and { config = compose_config } or nil,
		delivery = delivery,
		target_title = item.title,
	}
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.action.PreparedSendRequest? request
---@return wiremux.action.SendPreparationError[] errors
function M.prepare(item, preparation)
	local item_errors = validate_item(item)
	if #item_errors > 0 then
		return nil, item_errors
	end

	local compose_config, compose_prepare_errors = prepare_compose(item, preparation)
	if #compose_prepare_errors > 0 then
		return nil, compose_prepare_errors
	end

	local delivery, delivery_errors = prepare_delivery(item, preparation)
	if delivery == nil then
		return nil, delivery_errors
	end

	local capture, capture_errors = prepare_capture(item, preparation, compose_config)
	if capture == nil then
		return nil, capture_errors
	end

	return build_request(item, compose_config, delivery, capture), {}
end

return M
