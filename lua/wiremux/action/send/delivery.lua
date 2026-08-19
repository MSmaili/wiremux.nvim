local M = {}

---@alias wiremux.action.SendDeliveryErrorCode "invalid_delivery"|"backend_unavailable"|"delivery_failed"

---@class wiremux.action.SendDeliveryError
---@field code wiremux.action.SendDeliveryErrorCode
---@field message string

---@param code wiremux.action.SendDeliveryErrorCode
---@param message string
---@return wiremux.action.SendDeliveryError
local function delivery_error(code, message)
	return { code = code, message = message }
end

---Perform target selection and backend delivery for one prepared payload.
---@param payload string
---@param options wiremux.action.DeliveryOptions
---@param target_title? string
---@return boolean started
---@return wiremux.action.SendDeliveryError? error
function M.send(payload, options, target_title)
	if type(payload) ~= "string" or type(options) ~= "table" then
		return false, delivery_error(
			"invalid_delivery",
			"Failed to deliver payload: payload and delivery options are required"
		)
	end

	local backend = require("wiremux.backend").get()
	if backend == nil then
		return false, delivery_error("backend_unavailable", "Failed to deliver payload: no active backend")
	end

	local backend_options = {
		focus = options.focus,
		pre_keys = options.pre_keys,
		post_keys = options.post_keys,
	}
	local selected = false
	local function claim_selection()
		if selected then
			return false
		end
		selected = true
		return true
	end

	local ok, err = pcall(require("wiremux.core.action").run, {
		prompt = "Send to",
		behavior = options.behavior,
		mode = options.mode,
		filter = options.filter,
		target = options.target,
	}, {
		on_targets = function(targets, state)
			if claim_selection() then
				backend.send(payload, targets, backend_options, state)
			end
		end,
		on_definition = function(name, def, state)
			if not claim_selection() then
				return
			end
			local has_own_cmd = def.cmd ~= nil
			local create_def = vim.tbl_extend("force", {}, def, {
				cmd = def.cmd or payload,
				title = target_title,
			})
			local instance = backend.create(name, create_def, state)
			if instance and has_own_cmd then
				local sent = false
				backend.wait_for_ready(instance, { timeout_ms = def.startup_timeout }, function()
					if sent then
						return
					end
					sent = true
					backend.send(payload, { instance }, backend_options, state)
				end)
			end
		end,
	})
	if not ok then
		return false, delivery_error("delivery_failed", "Failed to deliver payload: " .. tostring(err))
	end
	return true, nil
end

return M
