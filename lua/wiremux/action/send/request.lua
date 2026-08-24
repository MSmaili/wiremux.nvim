local M = {}

local context = require("wiremux.context")
local validate = require("wiremux.utils.validate")

---@class wiremux.action.DeliveryOptions Immutable-by-ownership options consumed only by target selection and delivery.
---@field focus? boolean
---@field behavior wiremux.action.Behavior
---@field mode wiremux.ResolveMode
---@field target? string
---@field filter? wiremux.config.FilterConfig
---@field pre_keys? string|string[]
---@field post_keys? string|string[]

---@class wiremux.action.PreparedSendRequest Complete execution input fixed before picker or compose interaction.
---@field raw_text string Raw template text; never overwritten with a materialized payload.
---@field label string
---@field placeholder_capture wiremux.context.PlaceholderCapture Point-in-time capture owned by this request and transferred to its compose page when applicable.
---@field origin? wiremux.context.ResolverOrigin Source location transferred to a compose page for deferred resolution.
---@field compose? wiremux.config.ComposeSessionConfig
---@field delivery wiremux.action.DeliveryOptions
---@field target_title? string Target creation title, separate from the compose window title.

---@class wiremux.action.TargetSelection Call-level target selection, resolved and validated once per invocation.
---@field focus? boolean
---@field behavior wiremux.action.Behavior
---@field mode wiremux.ResolveMode
---@field target? string
---@field filter? wiremux.config.FilterConfig

---@class wiremux.action.ComposeSelection Compose value selected once from call options or action defaults.
---@field value? boolean|wiremux.config.ComposeOptions
---@field path string

---@class wiremux.action.SendPreparationContext
---@field selection wiremux.action.TargetSelection
---@field submit? boolean
---@field pre_keys? string|string[]
---@field post_keys? string|string[]
---@field compose wiremux.action.ComposeSelection
---@field global_compose wiremux.config.ComposeSessionConfig
---@field capture_memo table<string, string|false> Resolver results shared by every candidate of this call.
---@field compose_cache table<any, { config?: wiremux.config.ComposeSessionConfig, errors: wiremux.Error[] }> Resolved compose config, keyed on the selected value.

---Key for a nil compose selection, since nil cannot index the per-call cache.
local NO_COMPOSE = {}

---@param post_keys? string|string[]
---@return string[]
local function append_submit(post_keys)
	local result = type(post_keys) == "table" and vim.list_slice(post_keys) or { post_keys }
	table.insert(result, "Enter")
	return result
end

---Prepare call-level and global send configuration once for a public send invocation.
---Call-level invariants are validated here, so one invalid option aborts the invocation instead of
---warning once per library item.
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

	local resolved = {
		focus = vim.F.if_nil(call.focus, defaults.focus),
		behavior = vim.F.if_nil(call.behavior, defaults.behavior, "pick"),
		mode = vim.F.if_nil(call.mode, defaults.mode, "auto"),
		target = vim.F.if_nil(call.target, defaults.target),
		filter = vim.F.if_nil(call.filter, defaults.filter),
		submit = vim.F.if_nil(call.submit, defaults.submit),
		pre_keys = vim.F.if_nil(call.pre_keys, defaults.pre_keys),
		post_keys = vim.F.if_nil(call.post_keys, defaults.post_keys),
	}

	local errors = validate.send_options(resolved)
	if #errors > 0 then
		return nil, errors
	end

	return {
		selection = {
			focus = resolved.focus,
			behavior = resolved.behavior,
			mode = resolved.mode,
			target = resolved.target,
			filter = resolved.filter,
		},
		submit = resolved.submit,
		pre_keys = resolved.pre_keys,
		post_keys = resolved.post_keys,
		compose = call.compose ~= nil and { value = call.compose, path = "opts.compose" }
			or { value = defaults.compose, path = "actions.send.compose" },
		global_compose = config.ui.compose,
		capture_memo = {},
		compose_cache = {},
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

	-- Items sharing one compose value share one resolved config. resolve_compose deepcopies keymaps
	-- and wo, so this is the larger constant-factor win for a library.
	local key = selected == nil and NO_COMPOSE or selected
	local cached = preparation.compose_cache[key]
	if cached == nil then
		local config, errors = validate.resolve_compose(preparation.global_compose, selected, path)
		cached = { config = config, errors = errors }
		preparation.compose_cache[key] = cached
	end
	if #cached.errors > 0 then
		return nil, cached.errors
	end
	return cached.config, {}
end

---Combine the validated call-level selection with this item's own delivery overrides.
---@param item wiremux.action.SendItem
---@param preparation wiremux.action.SendPreparationContext
---@return wiremux.action.DeliveryOptions? delivery
---@return wiremux.Error[] errors
local function prepare_delivery(item, preparation)
	local submit = vim.F.if_nil(item.submit, preparation.submit)
	local pre_keys = vim.F.if_nil(item.pre_keys, preparation.pre_keys)
	local post_keys = vim.F.if_nil(item.post_keys, preparation.post_keys)

	local errors =
		validate.send_options({ submit = submit, pre_keys = pre_keys, post_keys = post_keys }, validate.ITEM_OPTIONS)
	if #errors > 0 then
		return nil, errors
	end

	local selection = preparation.selection
	return {
		focus = selection.focus,
		behavior = selection.behavior,
		mode = selection.mode,
		target = selection.target,
		filter = selection.filter,
		pre_keys = pre_keys,
		post_keys = submit and append_submit(post_keys) or post_keys,
	}, {}
end

---`context.capture` cannot throw: `validate.send_item` guaranteed a string value and every resolver is
---pcall'd inside `context.get`.
---@param item wiremux.action.SendItem
---@param memo table<string, string|false>
---@return wiremux.context.PlaceholderCapture capture
local function prepare_capture(item, memo)
	if item.placeholders == false then
		return { enabled = false, results = {} }
	end
	return context.capture(item.value, memo)
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

	local origin = compose_config and item.placeholders ~= false and context.capture_origin() or nil
	local capture = prepare_capture(item, preparation.capture_memo)

	return {
		raw_text = item.value,
		label = item.label or item.value,
		placeholder_capture = capture,
		origin = origin,
		compose = compose_config,
		delivery = delivery,
		target_title = item.title,
	}, {}
end

return M
