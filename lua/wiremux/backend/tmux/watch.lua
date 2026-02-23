local M = {}

local client = require("wiremux.backend.tmux.client")
local query = require("wiremux.backend.tmux.query")
local notify = require("wiremux.utils.notify")

local DEFAULTS = {
	interval_ms = 100,
	stable_polls = 3,
	timeout_ms = 3500,
}

---@param pane_id string
---@param callback fun(content: string)
local function capture(pane_id, callback)
	client.query_async({ query.capture_pane(pane_id) }, function(results)
		callback(results and results[1] or "")
	end)
end

---@param current string
---@param previous string
---@param baseline string
---@return boolean
local function has_settled(current, previous, baseline)
	return current == previous and current ~= baseline
end

---@param pane_id string
---@param callback fun()
---@param opts? { interval_ms?: number, stable_polls?: number, timeout_ms?: number }
function M.wait_for_ready(pane_id, callback, opts)
	opts = opts or {}
	local interval = opts.interval_ms or DEFAULTS.interval_ms
	local required_stable = opts.stable_polls or DEFAULTS.stable_polls
	local timeout = opts.timeout_ms or DEFAULTS.timeout_ms

	capture(pane_id, function(baseline)
		local elapsed = 0
		local previous = baseline
		local stable = 0

		local function poll()
			if elapsed >= timeout then
				notify.debug("watch: timeout after %dms, proceeding", elapsed)
				callback()
				return
			end

			capture(pane_id, function(current)
				if has_settled(current, previous, baseline) then
					stable = stable + 1
					notify.debug("watch: stable=%d/%d elapsed=%dms", stable, required_stable, elapsed)
					if stable >= required_stable then
						notify.debug("watch: ready after %dms", elapsed)
						callback()
						return
					end
				else
					stable = 0
				end

				previous = current
				elapsed = elapsed + interval
				vim.defer_fn(poll, interval)
			end)
		end

		vim.defer_fn(poll, interval)
	end)
end

return M
