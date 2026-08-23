local M = {}

---@class wiremux.ui.ComposePageCapture Extensible, controller-opaque point-in-time page capture.
---@field placeholder_capture wiremux.context.PlaceholderCapture
---@field origin? wiremux.context.ResolverOrigin

---@class wiremux.ui.ComposePage
---@field text string Raw template text edited without refreshing the page capture.
---@field capture any Opaque page-owned capture passed unchanged to confirmation.

---@class wiremux.ui.ComposeDraft
---@field pages wiremux.ui.ComposePage[]
---@field current_page number

---@param text? string
---@param capture? any
---@return wiremux.ui.ComposeDraft
function M.new(text, capture)
	return {
		pages = { { text = text or "", capture = capture } },
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
---@param capture? any
function M.append(draft, text, capture)
	table.insert(draft.pages, { text = text, capture = capture })
	draft.current_page = #draft.pages
end

---@param draft wiremux.ui.ComposeDraft
---@param text string
---@param capture? any
function M.replace(draft, text, capture)
	draft.pages = { { text = text, capture = capture } }
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
