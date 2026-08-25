local M = {}

---Minimum Neovim version that wiremux supports.
M.MIN_NVIM = "0.11"

---@return boolean
function M.supported()
	return vim.fn.has("nvim-" .. M.MIN_NVIM) == 1
end

---@return string
function M.requirement()
	return string.format("wiremux requires Neovim %s or later, found %s", M.MIN_NVIM, tostring(vim.version()))
end

return M
