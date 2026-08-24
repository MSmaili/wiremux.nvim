local M = {}

local context = require("wiremux.context")

---@class wiremux.action.ComposePageCapture
---@field placeholder_capture wiremux.context.PlaceholderCapture
---@field origin? wiremux.context.ResolverOrigin

---Create one prepared payload from a direct request without mutating its capture.
---`context.materialize` cannot throw here: `validate.send_item` guaranteed a string `raw_text` and
---`prepare_capture` guaranteed a `string|false` capture.
---@param request wiremux.action.PreparedSendRequest
---@return string payload
function M.direct(request)
	return context.materialize(request.raw_text, request.placeholder_capture)
end

---Resolve one compose placeholder through a temporary capture copy.
---@param capture wiremux.action.ComposePageCapture
---@param name string
---@return string? value
---@return string? error
function M.preview_placeholder(capture, name)
	local working = context.extend(capture.placeholder_capture, "{" .. name .. "}", capture.origin)
	if not working.enabled then
		return nil, "Placeholder replacement is disabled for this page."
	end
	local value = working.results[name]
	if type(value) ~= "string" then
		return nil, string.format("No value is available for {%s}.", name)
	end
	return value, nil
end

---Create one prepared payload from ordered raw compose pages and temporary working captures.
---@param pages wiremux.ui.ComposePage[]
---@return string? payload
---@return string? error
function M.compose(pages)
	if type(pages) ~= "table" or not vim.islist(pages) then
		return nil, "Failed to prepare compose payload: pages must be a list"
	end

	local payloads = {}
	for index, page in ipairs(pages) do
		local capture = type(page) == "table" and type(page.text) == "string" and page.capture or nil
		if type(capture) ~= "table" then
			return nil, string.format("Failed to prepare compose page %d: malformed page", index)
		end
		local ok, payload = pcall(function()
			local working = context.extend(capture.placeholder_capture, page.text, capture.origin)
			return context.materialize(page.text, working)
		end)
		if not ok then
			return nil, string.format("Failed to prepare compose page %d: %s", index, tostring(payload))
		end
		payloads[index] = payload:gsub("%s+$", "")
	end
	return table.concat(payloads, "\n\n"), nil
end

return M
