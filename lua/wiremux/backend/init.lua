local M = {}

function M.get()
	if vim.env.TMUX then
		return require("wiremux.backend.tmux")
	end
	error("wiremux: not in tmux")
end

return M
