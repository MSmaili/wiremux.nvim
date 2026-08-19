local M = {}

local context = require("wiremux.context")

---@alias wiremux.action.SendMaterializationErrorCode "invalid_request"|"direct_failed"|"invalid_pages"|"compose_page_failed"

---@class wiremux.action.SendMaterializationError
---@field code wiremux.action.SendMaterializationErrorCode
---@field message string
---@field page? integer

---@param code wiremux.action.SendMaterializationErrorCode
---@param message string
---@param page? integer
---@return wiremux.action.SendMaterializationError
local function materialization_error(code, message, page)
	return { code = code, message = message, page = page }
end

---@param text string
---@param capture wiremux.context.PlaceholderCapture
---@return string
local function materialize_text(text, capture)
	local working_capture = context.extend(capture, text)
	local payload = context.materialize(text, working_capture)
	assert(type(payload) == "string", "wiremux context materialization must return a string")
	return payload
end

---Create one prepared payload from a direct request without mutating its capture.
---@param request wiremux.action.PreparedSendRequest
---@return string? payload
---@return wiremux.action.SendMaterializationError? error
function M.direct(request)
	if type(request) ~= "table" or type(request.raw_text) ~= "string" then
		return nil, materialization_error(
			"invalid_request",
			"Failed to prepare direct payload: prepared request must contain raw text"
		)
	end

	local ok, payload = pcall(materialize_text, request.raw_text, request.placeholder_capture)
	if not ok then
		return nil, materialization_error(
			"direct_failed",
			"Failed to prepare direct payload: " .. tostring(payload)
		)
	end
	return payload, nil
end

---Create one prepared payload from ordered raw compose pages and temporary working captures.
---@param pages wiremux.ui.ComposePage[]
---@return string? payload
---@return wiremux.action.SendMaterializationError? error
function M.compose(pages)
	if type(pages) ~= "table" or not vim.islist(pages) then
		return nil, materialization_error(
			"invalid_pages",
			"Failed to prepare compose payload: pages must be a list"
		)
	end

	local payloads = {}
	for index, page in ipairs(pages) do
		local ok, payload = pcall(function()
			assert(type(page) == "table", "wiremux compose page must be a table")
			assert(type(page.text) == "string", "wiremux compose page text must be a string")
			assert(type(page.capture) == "table", "wiremux compose page capture must be a table")
			return materialize_text(page.text, page.capture.placeholder_capture)
		end)
		if not ok then
			return nil, materialization_error(
				"compose_page_failed",
				string.format("Failed to prepare compose page %d: %s", index, tostring(payload)),
				index
			)
		end
		payloads[index] = payload:gsub("%s+$", "")
	end
	return table.concat(payloads, "\n\n"), nil
end

return M
