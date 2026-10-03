local M = {}
M.__index = M

function M.new(opts)
	return setmetatable({ preview = require("wiremux.completion").preview_options(opts) }, M)
end

function M:enabled()
	return require("wiremux.completion").enabled()
end

function M:get_trigger_characters()
	return { "{" }
end

function M:get_completions(ctx, callback)
	callback({
		items = require("wiremux.completion").items(ctx.bufnr, ctx.line, ctx.cursor[1] - 1, ctx.cursor[2]),
		-- Recompute edit bounds when typing or deleting inside an existing token.
		is_incomplete_forward = true,
		is_incomplete_backward = true,
	})
end

function M:resolve(item, callback)
	callback(require("wiremux.completion").resolve(item, self.preview))
end

return M
