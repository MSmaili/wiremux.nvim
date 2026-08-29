local M = {}

local context = require("wiremux.context")
local compose_config = require("wiremux.ui.compose.config")
local validate = require("wiremux.utils.validate")

---@class wiremux.action.SendOptions One resolved option record. `submit` is folded into `post_keys`
---before delivery, so target selection and delivery ignore it. Read-only for consumers.
---@field focus? boolean
---@field behavior wiremux.action.Behavior
---@field mode wiremux.ResolveMode
---@field target? string
---@field filter? wiremux.config.FilterConfig
---@field submit? boolean
---@field pre_keys? string|string[]
---@field post_keys? string|string[]

---@class wiremux.action.PreparedSendRequest Complete execution input fixed before picker or compose interaction.
---@field raw_text string Raw template text; never overwritten with a resolved payload.
---@field label string
---@field source wiremux.context.Source Frozen source context, transferred to the compose page when applicable.
---@field compose? wiremux.config.ComposeSessionConfig
---@field delivery wiremux.action.SendOptions
---@field target_title? string Target creation title, separate from the compose window title.

---@class wiremux.action.ComposeSelection Compose value selected once from call options or action defaults.
---@field value? boolean|wiremux.config.ComposeOptions
---@field path string

---@class wiremux.action.SendPreparationContext
---@field options wiremux.action.SendOptions Call options resolved and checked one time.
---@field compose wiremux.action.ComposeSelection
---@field global_compose wiremux.config.GlobalComposeConfig
---@field origin wiremux.context.ResolverOrigin Source location captured one time for this call.

---@param post_keys? string|string[]
---@return string[]
local function append_submit(post_keys)
	local result = type(post_keys) == "table" and vim.list_slice(post_keys) or { post_keys }
	table.insert(result, "Enter")
	return result
end

---Prepare call-level and global send configuration once for a public send invocation.
---@param opts? wiremux.config.ActionConfig
---@param config wiremux.config.UserOptions
---@return wiremux.action.SendPreparationContext? context
---@return wiremux.Error[] errors
function M.prepare_context(opts, config)
	if opts ~= nil and type(opts) ~= "table" then
		return nil, { { path = "opts", message = "wiremux.send opts must be a table" } }
	end

	local defaults = vim.tbl_get(config, "actions", "send") or {}
	local call = opts or {}

	---@type wiremux.action.SendOptions
	local options = {
		focus = vim.F.if_nil(call.focus, defaults.focus),
		behavior = vim.F.if_nil(call.behavior, defaults.behavior, "pick"),
		mode = vim.F.if_nil(call.mode, defaults.mode, "auto"),
		target = vim.F.if_nil(call.target, defaults.target),
		filter = vim.F.if_nil(call.filter, defaults.filter),
		submit = vim.F.if_nil(call.submit, defaults.submit),
		pre_keys = vim.F.if_nil(call.pre_keys, defaults.pre_keys),
		post_keys = vim.F.if_nil(call.post_keys, defaults.post_keys),
	}

	local errors = validate.send_options(options)
	if #errors > 0 then
		return nil, errors
	end

	return {
		options = options,
		compose = call.compose ~= nil and { value = call.compose, path = "opts.compose" }
			or { value = defaults.compose, path = "actions.send.compose" },
		global_compose = config.ui.compose,
		origin = context.capture_origin(),
	}, {}
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.config.ComposeSessionConfig? config
---@return wiremux.Error[] errors
local function prepare_compose(item, preparation)
	local selected = preparation.compose.value
	local path = preparation.compose.path
	if item.compose ~= nil then
		selected = item.compose
		path = "item.compose"
	end

	local config, errors = compose_config.resolve(preparation.global_compose, selected, path)
	if #errors > 0 then
		return nil, errors
	end
	return config, {}
end

---Apply this item's own option overrides to the call options.
---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.action.SendOptions? options
---@return wiremux.Error[] errors
local function prepare_delivery(item, preparation)
	-- Absent keys stay absent, so they do not override the call options. A false value does override.
	local overrides = {
		submit = item.submit,
		pre_keys = item.pre_keys,
		post_keys = item.post_keys,
	}

	local errors = validate.send_item_options(overrides)
	if #errors > 0 then
		return nil, errors
	end

	local options = vim.tbl_extend("force", preparation.options, overrides)
	if options.submit then
		options.post_keys = append_submit(options.post_keys)
	end
	return options, {}
end

---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.action.PreparedSendRequest? request
---@return wiremux.Error[] errors
function M.prepare(item, preparation)
	local item_errors = validate.send_item(item)
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

	return {
		raw_text = item.value,
		label = item.label or item.value,
		source = { origin = preparation.origin, resolve = item.placeholders ~= false },
		compose = compose_config,
		delivery = delivery,
		target_title = item.title,
	}, {}
end

return M
