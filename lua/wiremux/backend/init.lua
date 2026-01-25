local M = {}

function M.get()
	if vim.env.TMUX then
		return require("wiremux.backend.tmux")
	end
	require("wiremux.utils.notify").error("wiremux requires tmux")
	return nil
end

return M
