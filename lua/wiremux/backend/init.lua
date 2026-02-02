local M = {}

function M.get()
	if vim.env.TMUX then
		return require("wiremux.backend.tmux")
	end
	require("wiremux.utils.notify").error(
		"wiremux requires tmux. Start tmux first: tmux new-session -s mysession"
	)
	return nil
end

return M
