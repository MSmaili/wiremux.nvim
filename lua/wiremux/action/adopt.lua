local M = {}
local instance = require("wiremux.core.instance")

local DEFAULT_LABEL_FORMAT = "%-18s %-6s %-5s"

---@class wiremux.action.AdoptOpts
---@field target? string Target name to assign when adopting unmanaged panes. Defaults to pane-<id>.
---@field filter? { instances?: fun(inst: wiremux.Instance, state: wiremux.State): boolean }
---@field format_item? fun(inst: wiremux.Instance, state: wiremux.State): string Format pane for picker display.

---@param state wiremux.State
local function update_statusline(state)
	local statusline = package.loaded["wiremux.statusline"]
	if statusline then
		statusline.update(state)
	end
end

---@param inst wiremux.Instance
---@param state wiremux.State
---@return string
local function default_format_item(inst, state)
	local label =
		string.format(DEFAULT_LABEL_FORMAT, inst.target or "(unmanaged)", instance.location(inst, state), inst.id)
	if inst.running_command and inst.running_command ~= "" then
		label = label .. " " .. inst.running_command
	end
	return label
end

---@param inst wiremux.Instance
---@param st wiremux.State
---@return boolean
local function default_filter(inst, st)
	if st.session_id and inst.session_id then
		return inst.session_id == st.session_id
	end
	return true
end

---@param panes wiremux.Instance[]
---@param st wiremux.State
---@param action_filter? { instances?: fun(inst: wiremux.Instance, state: wiremux.State): boolean }
---@return wiremux.Instance[]
local function get_adoptable_panes(panes, st, action_filter)
	local filter_fn = (action_filter and action_filter.instances) or default_filter

	return vim.iter(panes)
		:filter(function(inst)
			if inst.id == st.origin_pane_id then
				return false
			end
			return filter_fn(inst, st)
		end)
		:totable()
end

---@param opts? wiremux.action.AdoptOpts
function M.adopt(opts)
	opts = opts or {}

	local backend = require("wiremux.backend").get()
	local notify = require("wiremux.utils.notify")
	if not backend then
		return
	end

	local st = backend.state.get()
	local panes = get_adoptable_panes(st.panes or st.instances, st, opts.filter)
	if #panes == 0 then
		notify.warn("No adoptable panes")
		return
	end

	local format_item = opts.format_item or default_format_item
	local picker = require("wiremux.picker")
	picker.select(panes, {
		prompt = "Adopt target",
		format_item = function(inst)
			return format_item(inst, st)
		end,
	}, function(choice)
		if not choice then
			return
		end
		if backend.adopt(choice, st, { target = opts.target }) then
			update_statusline(st)
		end
	end)
end

return M
