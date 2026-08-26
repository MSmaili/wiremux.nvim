local M = {}

---@class wiremux.ui.ComposePage
---@field text string Raw template text edited without refreshing the page source.
---@field source any Opaque page-owned source context passed unchanged to confirmation.

---@class wiremux.ui.ComposeDraft
---@field pages wiremux.ui.ComposePage[]
---@field current_page number

---@param text? string
---@param source? any
---@return wiremux.ui.ComposeDraft
function M.new(text, source)
	return {
		pages = { { text = text or "", source = source } },
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
---@param source? any
function M.append(draft, text, source)
	table.insert(draft.pages, { text = text, source = source })
	draft.current_page = #draft.pages
end

---@param draft wiremux.ui.ComposeDraft
---@param text string
---@param source? any
function M.replace(draft, text, source)
	draft.pages = { { text = text, source = source } }
	draft.current_page = 1
end

---Delete the current page and select the next one, or clear the only page.
---@param draft wiremux.ui.ComposeDraft
---@return number current_page
function M.delete_current(draft)
	if #draft.pages == 1 then
		draft.pages[1].text = ""
	else
		table.remove(draft.pages, draft.current_page)
		if draft.current_page > #draft.pages then
			draft.current_page = 1
		end
	end
	return draft.current_page
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
