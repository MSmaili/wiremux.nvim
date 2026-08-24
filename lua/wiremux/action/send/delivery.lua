local M = {}

---Perform target selection and backend delivery for one prepared payload.
---@param payload string
---@param options wiremux.action.DeliveryOptions
---@param target_title? string
---@return boolean started
---@return string? error
function M.send(payload, options, target_title)
	local backend = require("wiremux.backend").get()
	if backend == nil then
		return false, "Failed to deliver payload: no active backend"
	end

	local backend_options = {
		focus = options.focus,
		pre_keys = options.pre_keys,
		post_keys = options.post_keys,
	}
	local ok, err = pcall(require("wiremux.core.action").run, {
		prompt = "Send to",
		behavior = options.behavior,
		mode = options.mode,
		filter = options.filter,
		target = options.target,
	}, {
		on_targets = function(targets, state)
			backend.send(payload, targets, backend_options, state)
		end,
		on_definition = function(name, def, state)
			local has_own_cmd = def.cmd ~= nil
			local create_def = vim.tbl_extend("force", {}, def, {
				cmd = def.cmd or payload,
				title = target_title,
			})
			local instance = backend.create(name, create_def, state)
			if instance and has_own_cmd then
				backend.wait_for_ready(instance, { timeout_ms = def.startup_timeout }, function()
					backend.send(payload, { instance }, backend_options, state)
				end)
			end
		end,
	})
	if not ok then
		return false, "Failed to deliver payload: " .. tostring(err)
	end
	return true, nil
end

return M
