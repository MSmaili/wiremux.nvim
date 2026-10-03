local M = {}
M.__index = M

local source_id
local registered_source

function M.new(opts)
	return setmetatable({ preview = require("wiremux.completion").preview_options(opts) }, M)
end

---Call after cmp has loaded and compose has been used. Registration is idempotent.
---@param opts? table Completion options; explicit options update an existing registration.
---@return number
function M.register(opts)
	if not source_id then
		registered_source = M.new(opts)
		source_id = require("cmp").register_source("wiremux", registered_source)
	elseif opts ~= nil then
		registered_source.preview = require("wiremux.completion").preview_options(opts)
	end
	return source_id
end

function M:is_available()
	return require("wiremux.completion").enabled()
end

function M:get_trigger_characters()
	return { "{" }
end

function M:get_keyword_pattern()
	return [[{\%([A-Za-z_][A-Za-z0-9_]*\)\?]]
end

function M:get_position_encoding_kind()
	return "utf-8"
end

function M:complete(params, callback)
	local ctx = params.context
	callback({
		items = require("wiremux.completion").items(ctx.bufnr, ctx.cursor_line, ctx.cursor.row - 1, ctx.cursor.col - 1),
		isIncomplete = true,
	})
end

function M:resolve(item, callback)
	callback(require("wiremux.completion").resolve(item, self.preview))
end

return M
