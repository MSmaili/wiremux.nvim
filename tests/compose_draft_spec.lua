---@module 'luassert'

describe("compose draft", function()
	local draft

	before_each(function()
		package.loaded["wiremux.ui.compose.draft"] = nil
		draft = require("wiremux.ui.compose.draft")
	end)

	it("saves edits without changing source identity or contents", function()
		local source = {
			origin = { bufnr = 7, path = "/a.lua", row = 1, col = 0, selection = "chosen", line = "text" },
			resolve = true,
		}
		local state = draft.new("first", source)

		draft.save(state, "edited")

		assert.are.equal(1, state.current_page)
		assert.are.equal("edited", draft.current(state).text)
		assert.are.equal(source, draft.current(state).source)
		assert.are.equal("chosen", draft.current(state).source.origin.selection)
	end)

	it("keeps distinct sources for identical raw text", function()
		local first_source = { marker = "first" }
		local second_source = { marker = "second" }
		local state = draft.new("same", first_source)
		draft.append(state, "same", second_source)

		assert.are.equal(first_source, state.pages[1].source)
		assert.are.equal(second_source, state.pages[2].source)
		assert.are_not.equal(state.pages[1].source, state.pages[2].source)
	end)

	it("appends and selects a page with only its incoming source", function()
		local first_source = { value = "one" }
		local second_source = { value = "two" }
		local state = draft.new("first", first_source)
		draft.append(state, "second", second_source)

		assert.are.equal(2, state.current_page)
		assert.are.equal("second", draft.current(state).text)
		assert.are.equal(second_source, draft.current(state).source)
		assert.are.equal(first_source, state.pages[1].source)
	end)

	it("replaces the complete draft and drops old source references", function()
		local first_source = { value = "one" }
		local second_source = { value = "two" }
		local replacement_source = { value = "replacement" }
		local state = draft.new("first", first_source)
		draft.append(state, "second", second_source)
		local old_pages = state.pages

		draft.replace(state, "replacement", replacement_source)

		assert.are.equal(1, #state.pages)
		assert.are.equal(1, state.current_page)
		assert.are_not.equal(old_pages, state.pages)
		assert.are.same({ text = "replacement", source = replacement_source }, state.pages[1])
		assert.are_not.equal(first_source, state.pages[1].source)
		assert.are_not.equal(second_source, state.pages[1].source)
	end)

	it("wraps navigation without swapping page sources", function()
		local sources = { { page = 1 }, { page = 2 }, { page = 3 } }
		local state = draft.new("first", sources[1])
		draft.append(state, "second", sources[2])
		draft.append(state, "third", sources[3])

		assert.are.equal(1, draft.next(state))
		assert.are.equal(sources[1], draft.current(state).source)
		assert.are.equal(3, draft.previous(state))
		assert.are.equal(sources[3], draft.current(state).source)
		assert.are.equal(2, draft.previous(state))
		assert.are.equal(sources[2], draft.current(state).source)
		for index, source in ipairs(sources) do
			assert.are.equal(source, state.pages[index].source)
		end
	end)

	it("does not navigate a one-page draft", function()
		local state = draft.new("only", {})
		assert.are.equal(1, draft.previous(state))
		assert.are.equal(1, draft.next(state))
	end)

	it("evaluates emptiness across all pages", function()
		local state = draft.new(" \n\t", {})
		draft.append(state, "", {})
		assert.is_true(draft.is_empty(state))

		draft.save(state, "content")
		assert.is_false(draft.is_empty(state))
	end)
end)
