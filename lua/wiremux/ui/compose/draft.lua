local M = {}

---@class wiremux.ui.ComposePage
---@field text string
---@field meta? any

---@class wiremux.ui.ComposeDraft
---@field pages wiremux.ui.ComposePage[]
---@field current_page number

---@param text? string
---@param meta? any
---@return wiremux.ui.ComposeDraft
function M.new(text, meta)
	return {
		pages = { { text = text or "", meta = meta } },
		current_page = 1,
	}
end

---@param draft wiremux.ui.ComposeDraft
---@return wiremux.ui.ComposePage
function M.current(draft)
	return draft.pages[draft.current_page]
end

---@param draft wiremux.ui.ComposeDraft
---@param text string
function M.save(draft, text)
	M.current(draft).text = text
end

---@param draft wiremux.ui.ComposeDraft
---@param text string
---@param meta? any
function M.append(draft, text, meta)
	table.insert(draft.pages, { text = text, meta = meta })
	draft.current_page = #draft.pages
end

---@param draft wiremux.ui.ComposeDraft
---@param text string
---@param meta? any
function M.replace(draft, text, meta)
	draft.pages = { { text = text, meta = meta } }
	draft.current_page = 1
end

---@param draft wiremux.ui.ComposeDraft
---@return number
function M.previous(draft)
	if #draft.pages > 1 then
		draft.current_page = ((draft.current_page - 2) % #draft.pages) + 1
	end
	return draft.current_page
end

---@param draft wiremux.ui.ComposeDraft
---@return number
function M.next(draft)
	if #draft.pages > 1 then
		draft.current_page = (draft.current_page % #draft.pages) + 1
	end
	return draft.current_page
end

---@param draft wiremux.ui.ComposeDraft
---@return boolean
function M.is_empty(draft)
	for _, page in ipairs(draft.pages) do
		if page.text:match("%S") then
			return false
		end
	end
	return true
end

return M
