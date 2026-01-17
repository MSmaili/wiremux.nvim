local M = {}

local notify = require("wiremux.utils.notify")

local SEPARATOR = "<<<WIREMUX>>>"

---@alias wiremux.tmux.Command string[] A tmux command as an array of arguments

---@param cmds wiremux.tmux.Command[]
---@param opts? { stdin?: string }
---@return string?
local function exec(cmds, opts)
	opts = opts or {}

	local batch = {}
	for i, cmd in ipairs(cmds) do
		if i > 1 then
			table.insert(batch, ";")
		end
		vim.list_extend(batch, cmd)
	end

	local full = vim.list_extend({ "tmux" }, batch)
	local result = vim.system(full, { text = true, stdin = opts.stdin }):wait()

	if result.code ~= 0 then
		notify.error("tmux: " .. (result.stderr or "failed"))
		return nil
	end
	return vim.trim(result.stdout or "")
end

---Execute commands
---@param cmds wiremux.tmux.Command[]
---@param opts? { stdin?: string }
---@return string?
function M.execute(cmds, opts)
	return exec(cmds, opts)
end

---Execute queries and parse results
---@param cmds wiremux.tmux.Command[]
---@return string[]
function M.query(cmds)
	local with_sep = {}
	for i, cmd in ipairs(cmds) do
		if i > 1 then
			table.insert(with_sep, { "display", "-p", SEPARATOR })
		end
		table.insert(with_sep, cmd)
	end

	local out = exec(with_sep)
	if not out then
		return {}
	end

	return vim.split(out, SEPARATOR .. "\n", { plain = true, trimempty = false })
end

---@return boolean
function M.is_available()
	return vim.env.TMUX ~= nil
end

return M
