local M = {}

local levels = vim.log.levels

---@type table<wiremux.config.LogLevel, integer>
local level_priority = {
	off = 0,
	error = 1,
	warn = 2,
	info = 3,
	debug = 4,
}

---Check whether we should show this level of logs
---@param msg_level wiremux.config.LogLevel
---@return boolean
local function should_log(msg_level)
	local ok, config = pcall(require, "wiremux.config")
	if not ok then
		return true
	end
	local config_level = config.opts.log_level or "warn"
	local config_priority = level_priority[config_level] or 2
	local msg_priority = level_priority[msg_level] or 0

	return msg_priority <= config_priority
end

--- Unified notification helper
---@param msg string|string[]
---@param level? integer vim.log.levels.*
---@param title? string
local function notify(msg, level, title)
	if type(msg) == "table" then
		msg = table.concat(msg, "\n")
	end

	vim.schedule(function()
		vim.notify(msg, level or levels.INFO, {
			title = title or "Wiremux",
		})
	end)
end

---@param msg string|string[]
function M.info(msg)
	if should_log("info") then
		notify(msg, levels.INFO)
	end
end

---@param msg string|string[]
function M.warn(msg)
	if should_log("warn") then
		notify(msg, levels.WARN)
	end
end

---@param msg string|string[]
function M.error(msg)
	if should_log("error") then
		notify(msg, levels.ERROR)
	end
end

---@param msg string|string[]
---@param ... any Optional values for string.format
function M.debug(msg, ...)
	if not should_log("debug") then
		return
	end

	local text
	if type(msg) == "string" and select("#", ...) > 0 then
		text = string.format(msg, ...)
	else
		text = type(msg) == "string" and msg or vim.inspect(msg)
	end

	notify("[DEBUG] " .. text, levels.DEBUG)
end

return M
