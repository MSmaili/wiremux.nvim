local M = {}

---@class wiremux.backend.StateApi
---@field get fun(): wiremux.State
---@field get_async fun(callback: fun(state: wiremux.State))
---@field set fun(state: wiremux.State)

---@class wiremux.backend.Adapter
---@field name string
---@field state wiremux.backend.StateApi
---@field send fun(text: string, targets: wiremux.Instance[], opts: table?, state: wiremux.State)
---@field create fun(target_name: string, def: wiremux.target.definition, state: wiremux.State): wiremux.Instance?
---@field focus fun(target: wiremux.Instance)
---@field toggle_visibility fun(state: wiremux.State)
---@field close fun(targets: wiremux.Instance[], state: wiremux.State)
---@field adopt fun(target: wiremux.Pane, state: wiremux.State, opts?: table): boolean?
---@field wait_for_ready fun(inst: wiremux.Instance, opts: table?, callback: fun())

local backend_names = { "tmux" }

local backend_loaders = {
	tmux = function()
		if vim.env.TMUX then
			return require("wiremux.backend.tmux")
		end
		return nil
	end,
}

---@return wiremux.backend.Adapter?
function M.get()
	for _, name in ipairs(backend_names) do
		local backend = backend_loaders[name]()
		if backend then
			return backend
		end
	end

	require("wiremux.utils.notify").error(
		"wiremux requires a supported backend. Start tmux first: tmux new-session -s mysession"
	)
	return nil
end

return M
