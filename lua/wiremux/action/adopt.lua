local M = {}

local DEFAULT_LABEL_FORMAT = "%-18s %-6s %-5s"

---@class wiremux.action.AdoptOpts
---@field target? string Target name to assign when adopting unmanaged panes. Defaults to pane-<id>.
---@field filter? { instances?: fun(inst: wiremux.Pane, state: wiremux.State): boolean }
---@field format_item? fun(inst: wiremux.Pane, state: wiremux.State): string Format pane for picker display.

---@param state wiremux.State
local function update_statusline(state)
	local statusline = package.loaded["wiremux.statusline"]
	if statusline then
		statusline.update(state)
	end
end

---@param id string?
---@return string
local function pane_id(id)
	return (id and id:match("%d+")) or id or "?"
end

---@param inst wiremux.Pane
---@return string
local function default_target_name(inst)
	return "pane-" .. pane_id(inst.id)
end

---@param inst wiremux.Pane
---@return string
local function pane_location(inst)
	if inst.window_index and inst.pane_index then
		return string.format("%s:%s", inst.window_index, inst.pane_index)
	end
	if inst.window_index then
		return tostring(inst.window_index)
	end
	if inst.window_name and inst.window_name ~= "" then
		return inst.window_name
	end
	return "-"
end

---@param inst wiremux.Pane
---@return string
local function default_format_item(inst)
	local label = string.format(DEFAULT_LABEL_FORMAT, inst.target or "(unmanaged)", pane_location(inst), inst.id or "?")
	if inst.running_command and inst.running_command ~= "" then
		label = label .. " " .. inst.running_command
	end
	return label
end

---@param inst wiremux.Pane
---@param st wiremux.State
---@return boolean
local function default_filter(inst, st)
	if st.session_id and inst.session_id then
		return inst.session_id == st.session_id
	end
	return true
end

---@param panes wiremux.Pane[]
---@param st wiremux.State
---@param action_filter? { instances?: fun(inst: wiremux.Pane, state: wiremux.State): boolean }
---@return wiremux.Pane[]
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

	local format_item = default_format_item
	if opts.format_item then
		format_item = function(inst)
			return opts.format_item(inst, st)
		end
	end

	local picker = require("wiremux.picker")
	picker.select(panes, {
		prompt = "Adopt target",
		format_item = format_item,
	}, function(choice)
		if not choice then
			return
		end
		local target_name = opts.target
		if not choice.target and (not target_name or target_name == "") then
			target_name = default_target_name(choice)
		end
		if backend.adopt(choice, st, { target = target_name }) then
			update_statusline(st)
		end
	end)
end

return M
