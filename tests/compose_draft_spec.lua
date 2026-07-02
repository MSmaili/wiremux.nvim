---@module 'luassert'

describe("compose draft", function()
	local draft

	before_each(function()
		package.loaded["wiremux.ui.compose.draft"] = nil
		draft = require("wiremux.ui.compose.draft")
	end)

	it("creates and saves a first page without changing metadata", function()
		local meta = { value = "captured" }
		local state = draft.new("first", meta)

		draft.save(state, "edited")

		assert.are.equal(1, state.current_page)
		assert.are.equal("edited", draft.current(state).text)
		assert.are.equal(meta, draft.current(state).meta)
	end)

	it("appends and selects pages", function()
		local state = draft.new("first", "one")
		draft.append(state, "second", "two")

		assert.are.equal(2, state.current_page)
		assert.are.equal("second", draft.current(state).text)
		assert.are.equal("two", draft.current(state).meta)
	end)

	it("replaces the complete draft", function()
		local state = draft.new("first")
		draft.append(state, "second")
		draft.replace(state, "replacement", "meta")

		assert.are.equal(1, #state.pages)
		assert.are.equal(1, state.current_page)
		assert.are.same({ text = "replacement", meta = "meta" }, state.pages[1])
	end)

	it("wraps previous and next navigation", function()
		local state = draft.new("first")
		draft.append(state, "second")
		draft.append(state, "third")

		assert.are.equal(1, draft.next(state))
		assert.are.equal(3, draft.previous(state))
		assert.are.equal(2, draft.previous(state))
	end)

	it("does not navigate a one-page draft", function()
		local state = draft.new("only")
		assert.are.equal(1, draft.previous(state))
		assert.are.equal(1, draft.next(state))
	end)

	it("evaluates emptiness across all pages", function()
		local state = draft.new(" \n\t")
		draft.append(state, "")
		assert.is_true(draft.is_empty(state))

		draft.save(state, "content")
		assert.is_false(draft.is_empty(state))
	end)
end)
