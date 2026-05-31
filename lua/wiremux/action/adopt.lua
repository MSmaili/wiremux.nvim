local M = {}

---@class wiremux.action.AdoptOpts
---@field target? string Target name to assign when adopting unmanaged panes.
---@field filter? { instances?: fun(inst: wiremux.Pane, state: wiremux.State): boolean }

---@param state wiremux.State
local function update_statusline(state)
	local statusline = package.loaded["wiremux.statusline"]
	if statusline then
		statusline.update(state)
	end
end

---@param inst wiremux.Pane
---@return string
local function format_instance(inst)
	local name = inst.window_name and inst.window_name ~= "" and inst.window_name or inst.target or "unmanaged"
	local id = inst.id:match("%d+") or inst.id
	local label = string.format("%s %s", name, id)
	if inst.running_command and inst.running_command ~= "" then
		label = label .. string.format(" [%s]", inst.running_command)
	end
	return label
end

---@param inst wiremux.Pane
---@param st wiremux.State
---@return boolean
local function default_filter(inst, st)
	return inst.target ~= nil and inst.target ~= "" and inst.session_id == st.session_id
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

	local picker = require("wiremux.picker")
	picker.select(panes, {
		prompt = "Adopt target",
		format_item = format_instance,
	}, function(choice)
		if not choice then
			return
		end
		if not choice.target and (not opts.target or opts.target == "") then
			notify.warn("Adopting unmanaged panes requires opts.target")
			return
		end
		if backend.adopt(choice, st, { target = opts.target }) then
			update_statusline(st)
		end
	end)
end

return M
