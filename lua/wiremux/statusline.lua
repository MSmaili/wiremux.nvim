local M = {}

local notify = require("wiremux.utils.notify")

---@class wiremux.statusline.Info
---@field loading boolean true until first successful fetch
---@field count integer Number of wiremux instances
---@field last_used? { id: string, target: string, kind: "pane"|"window", name: string }

---@type wiremux.statusline.Info
local cache = {
	loading = true,
	count = 0,
	last_used = nil,
}

local REFRESH_INTERVAL = 30000
local DEBOUNCE_MS = 500
local timer = nil
local debounce_timer = nil
local initialized = false
local fetching = false
local augroup = vim.api.nvim_create_augroup("WiremuxStatusline", { clear = true })
local component_func = nil

---Convert wiremux.State to statusline info with filtering
---@param state wiremux.State
---@return wiremux.statusline.Info
local function state_to_info(state)
	-- Get filter from config
	local config = require("wiremux.config")
	local filter_fn = config.opts.filter.instances

	local resolver = require("wiremux.core.resolver")
	local filtered_instances = resolver.filter_instances(state.instances, filter_fn, state)

	local count = #filtered_instances
	local last_used = nil

	-- Find last_used from filtered instances only
	if state.last_used_target_id then
		for _, inst in ipairs(filtered_instances) do
			if inst.id == state.last_used_target_id then
				last_used = {
					id = inst.id,
					target = inst.target,
					kind = inst.kind,
					name = inst.target,
				}
				break
			end
		end
	end

	-- Fallback to first filtered instance
	if not last_used and count > 0 then
		local inst = filtered_instances[1]
		last_used = {
			id = inst.id,
			target = inst.target,
			kind = inst.kind,
			name = inst.target,
		}
	end

	return {
		loading = false,
		count = count,
		last_used = last_used,
	}
end

---Update cache in-place to preserve table reference
---@param info wiremux.statusline.Info
local function update_cache_in_place(info)
	cache.loading = info.loading
	cache.count = info.count
	cache.last_used = info.last_used
end

---Fetch state async and update cache
local function fetch()
	if fetching then
		return
	end
	fetching = true

	require("wiremux.backend.tmux.state").get_async(function(state)
		fetching = false
		if not state then
			notify.debug("statusline: fetch failed")
			return
		end

		update_cache_in_place(state_to_info(state))
		notify.debug("statusline: updated (count=%d)", cache.count)

		-- Refresh statusline
		vim.cmd("redrawstatus")
	end)
end

---Debounced fetch — collapses rapid calls into a single fetch
local function fetch_debounced()
	if debounce_timer then
		debounce_timer:stop()
		debounce_timer:close()
	end
	debounce_timer = vim.uv.new_timer()
	debounce_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(fetch))
end

---Get statusline info (non-blocking, returns cached data)
---First call initializes the timer and triggers an async fetch
---@return wiremux.statusline.Info
function M.get_info()
	if not initialized then
		initialized = true

		timer = vim.uv.new_timer()
		timer:start(REFRESH_INTERVAL, REFRESH_INTERVAL, vim.schedule_wrap(fetch))

		autocmd_id = vim.api.nvim_create_autocmd("FocusGained", {
			group = augroup,
			callback = fetch_debounced,
		})

		fetch()
	end

	return cache
end

---Update statusline from known state (no IPC)
---@param state wiremux.State
function M.update(state)
	update_cache_in_place(state_to_info(state))
	-- Refresh statusline (works with all statusline plugins)
	vim.cmd("redrawstatus")
end

---Returns a statusline component function
---Only shows when tmux backend is available. Returns empty string otherwise.
---Usage: { require("wiremux").statusline.component() }
---@return function
function M.component()
	if not component_func then
		component_func = function()
			-- Only show when tmux backend is available
			if not require("wiremux.backend.tmux.client").is_available() then
				return ""
			end

			local info = M.get_info()

			if info.loading then
				return "󰫃 wiremux"
			elseif info.count == 0 then
				return ""
			end

			local text = string.format("󰆍 %d", info.count)
			if info.last_used then
				text = text .. string.format(" [%s]", info.last_used.name)
			end
			return text
		end
	end
	return component_func
end

return M
