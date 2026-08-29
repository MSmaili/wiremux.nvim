local M = {}

local function format_size(bytes)
	if bytes < 1024 then
		return string.format("%d B", bytes)
	end
	if bytes < 1024 * 1024 then
		return string.format("%.1f KB", bytes / 1024)
	end
	return string.format("%.1f MB", bytes / (1024 * 1024))
end

---@param entry wiremux.history.Entry
---@return string
local function format_entry(entry)
	return string.format(
		"%s  [%s]  %s",
		os.date("%Y-%m-%d %H:%M", entry.created_at),
		format_size(entry.size),
		entry.preview
	)
end

function M.history()
	local history = require("wiremux.history")
	local entries, err = history.list()
	local notify = require("wiremux.utils.notify")
	if not entries then
		notify.error("Failed to load compose history: " .. tostring(err))
		return
	end
	if err then
		notify.warn("Failed to prune stale compose history files: " .. tostring(err))
	end
	if #entries == 0 then
		local disabled = require("wiremux.config").get().ui.compose.history_limit == 0
		notify.warn(disabled and "Compose history is disabled" or "No compose history")
		return
	end

	require("wiremux.picker").select(entries, {
		prompt = "Compose history",
		format_item = format_entry,
		preview_file = history.path,
	}, function(choice)
		if not choice then
			return
		end
		local payload, read_err = history.read(choice)
		if payload == nil then
			notify.error("Failed to load compose history payload: " .. tostring(read_err))
			return
		end
		require("wiremux.action.send").send({
			value = payload,
			compose = true,
			placeholders = false,
		})
	end)
end

return M
