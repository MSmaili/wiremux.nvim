local M = {}

--- Setup wiremux with user configuration
---@param opts? wiremux.config.UserOptions
function M.setup(opts)
	require("wiremux.config").setup(opts)
end

function M.send(text, opts)
	--TODO
end

return M
