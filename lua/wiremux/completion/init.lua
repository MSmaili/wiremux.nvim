local M = {}

-- Identify a page source without keeping its captured editor context alive.
local source_ids = setmetatable({}, { __mode = "k" })
local next_source_id = 0

local descriptions = {
	file = "Source file path",
	filename = "Source file name",
	position = "Source file path and position",
	line = "Source line text",
	selection = "Source visual selection",
	this = "Source position and visual selection, when present",
	diagnostics = "Diagnostics on the source line",
	diagnostics_all = "All diagnostics in the source buffer",
	buffers = "Paths of loaded, listed buffers",
	quickfix = "Quickfix list",
	changes = "Git diff against HEAD for the source file",
}

---Availability checks must never load compose or evaluate a resolver.
---@param buf? number
---@return boolean
function M.enabled(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].wiremux_compose ~= true then
		return false
	end
	local compose = package.loaded["wiremux.ui.compose"]
	local source = compose and compose.get_source(buf)
	return type(source) == "table" and source.resolve == true
end

---@param opts? table
---@return {max_lines: integer, max_bytes: integer}?
function M.preview_options(opts)
	local preview = opts and opts.preview
	if preview == nil or preview == false then
		return nil
	end
	if preview == true then
		preview = {}
	end
	assert(type(preview) == "table", "wiremux completion preview must be a boolean or table")
	local limits = { max_lines = 10, max_bytes = 2048 }
	for name, default in pairs(limits) do
		local value = preview[name] == nil and default or preview[name]
		assert(
			type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value),
			"wiremux completion preview." .. name .. " must be a positive integer"
		)
		limits[name] = value
	end
	return limits
end

---Build plain-text completion edits using zero-based UTF-8 byte positions.
---Only the placeholder surrounding the cursor is replaced, including an existing }.
---@param buf number
---@param line string
---@param row integer
---@param col integer
---@return table[]
function M.items(buf, line, row, col)
	if buf ~= vim.api.nvim_get_current_buf() or not M.enabled(buf) then
		return {}
	end
	local before = line:sub(1, col)
	local first = before:match("(){[A-Za-z_][A-Za-z0-9_]*$") or before:match("(){$")
	if not first then
		return {}
	end
	local suffix = line:sub(col + 1):match("^[A-Za-z0-9_]*}?")
	local source = package.loaded["wiremux.ui.compose"].get_source(buf)
	if not source_ids[source] then
		next_source_id = next_source_id + 1
		source_ids[source] = next_source_id
	end
	local items = {}
	for _, name in ipairs(require("wiremux.context").names()) do
		local label = "{" .. name .. "}"
		items[#items + 1] = {
			label = label,
			kind = 6, -- CompletionItemKind.Variable
			insertTextFormat = 1, -- PlainText; no snippet engine required.
			detail = "Wiremux placeholder",
			documentation = { kind = "plaintext", value = descriptions[name] or "Custom placeholder" },
			data = { wiremux = { buf = buf, source_id = source_ids[source], name = name } },
			textEdit = {
				newText = label,
				range = {
					start = { line = row, character = first - 1 },
					["end"] = { line = row, character = col + #suffix },
				},
			},
		}
	end
	return items
end

---Bound the displayed value, scanning only the bounded prefix of a large result.
local function truncate(value, limits)
	local last = math.min(#value, limits.max_bytes)
	-- Do not leave a partial UTF-8 character at the byte boundary.
	while last > 0 do
		local next_byte = value:byte(last + 1)
		if not next_byte or next_byte < 128 or next_byte > 191 then
			break
		end
		last = last - 1
	end
	local text = value:sub(1, last)
	local offset = 1
	for _ = 1, limits.max_lines do
		local newline = text:find("\n", offset, true)
		if not newline then
			return text, last < #value
		end
		offset = newline + 1
	end
	return text:sub(1, offset - 2), true
end

---Resolve only the requested item's documentation, never its insertion text.
---@param item table
---@param limits? {max_lines: integer, max_bytes: integer}
---@return table
function M.resolve(item, limits)
	local data = item.data and item.data.wiremux
	if not limits or not data or data.buf ~= vim.api.nvim_get_current_buf() or not M.enabled(data.buf) then
		return item
	end
	local source = package.loaded["wiremux.ui.compose"].get_source(data.buf)
	if source_ids[source] ~= data.source_id then
		return item
	end
	local value = require("wiremux.context").get(data.name, source.origin)
	if value == nil then
		value = "No value is available for {" .. data.name .. "}."
	elseif value == "" then
		value = "(empty)"
	end
	local text, truncated = truncate(value, limits)
	-- A value may itself contain Markdown fences; keep it literal in the popup.
	local fence_length = 3
	for backticks in text:gmatch("`+") do
		fence_length = math.max(fence_length, #backticks + 1)
	end
	local fence = string.rep("`", fence_length)
	local syntax = data.name == "changes" and "diff" or "text"
	local documentation = (descriptions[data.name] or "Custom placeholder")
		.. "\n\n"
		.. fence
		.. syntax
		.. "\n"
		.. text
		.. "\n"
		.. fence
		.. (truncated and "\n\nPreview truncated." or "")
	return vim.tbl_extend("force", {}, item, { documentation = { kind = "markdown", value = documentation } })
end

return M
