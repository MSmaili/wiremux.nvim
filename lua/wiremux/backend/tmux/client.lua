local M = {}

local notify = require("wiremux.utils.notify")

local SEPARATOR = "<<<WIREMUX>>>"

---@alias wiremux.tmux.Command string[] A tmux command as an array of arguments

---Build command batch with separators for multiple commands
---@param cmds wiremux.tmux.Command[]
---@return string[]
local function build_batch(cmds)
	local batch = {}
	for i, cmd in ipairs(cmds) do
		if i > 1 then
			table.insert(batch, ";")
		end
		vim.list_extend(batch, cmd)
	end
	return batch
end

---Add result separators between commands for parsing
---@param cmds wiremux.tmux.Command[]
---@return wiremux.tmux.Command[]
local function add_separators(cmds)
	local with_sep = {}
	for i, cmd in ipairs(cmds) do
		if i > 1 then
			table.insert(with_sep, { "display", "-p", SEPARATOR })
		end
		table.insert(with_sep, cmd)
	end
	return with_sep
end

---Parse query output with separators
---@param output string
---@return string[]
local function parse_query_output(output)
	return vim.split(output, SEPARATOR .. "\n", { plain = true, trimempty = false })
end

---Execute commands (blocking)
---@param cmds wiremux.tmux.Command[]
---@param opts? { stdin?: string }
---@return string?
local function exec(cmds, opts)
	opts = opts or {}
	local batch = build_batch(cmds)
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

---Execute queries and parse results (blocking)
---@param cmds wiremux.tmux.Command[]
---@return string[]
function M.query(cmds)
	local with_sep = add_separators(cmds)
	local out = exec(with_sep)
	if not out then
		return {}
	end
	return parse_query_output(out)
end

---Execute queries asynchronously
---@param cmds wiremux.tmux.Command[]
---@param callback fun(results: string[]?) Callback with results or nil on error
function M.query_async(cmds, callback)
	local with_sep = add_separators(cmds)
	local batch = build_batch(with_sep)
	local full = vim.list_extend({ "tmux" }, batch)

	vim.system(full, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				notify.error("tmux: " .. (result.stderr or "failed"))
				callback(nil)
				return
			end

			local out = vim.trim(result.stdout or "")
			local results = parse_query_output(out)
			callback(results)
		end)
	end)
end

---@return boolean
function M.is_available()
	return vim.env.TMUX ~= nil
end

return M
