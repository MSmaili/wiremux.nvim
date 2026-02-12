local M = {}

local resolver = require("wiremux.core.resolver")

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

local augroup = vim.api.nvim_create_augroup("WiremuxStatusline", { clear = true })
local component_func = nil
local autocmd_set = false

---Convert wiremux.State to statusline info with filtering
---@param state wiremux.State
---@return wiremux.statusline.Info
local function state_to_info(state)
	local filtered_instances = resolver.filter_instances(state.instances, state, nil)

	local count = #filtered_instances
	local last_used = nil

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

---Update cache from state
---@param state wiremux.State
function M.update(state)
	local info = state_to_info(state)
	cache.loading = info.loading
	cache.count = info.count
	cache.last_used = info.last_used

	vim.cmd("redrawstatus")
end

---Get statusline info
---Returns cached info.
---@return wiremux.statusline.Info
function M.get_info()
	return cache
end

---Refresh statusline on FocusGained
local function refresh()
	local backend = require("wiremux.backend.tmux")
	backend.state.get_async(function(state)
		if state then
			M.update(state)
		end
	end)
end

---Returns a statusline component function
---Only shows when backend is available. Returns empty string otherwise.
---Usage: { require("wiremux").statusline.component() }
---@return function
function M.component()
	if not component_func then
		if not autocmd_set then
			autocmd_set = true
			vim.api.nvim_create_autocmd("FocusGained", {
				group = augroup,
				callback = refresh,
			})
			vim.schedule(refresh)
		end

		component_func = function()
			if cache.loading then
				return ""
			end

			if cache.count == 0 then
				return ""
			end

			local text = string.format("󰆍 %d", cache.count)
			if cache.last_used then
				text = text .. string.format(" [%s]", cache.last_used.name)
			end
			return text
		end
	end
	return component_func
end

return M
