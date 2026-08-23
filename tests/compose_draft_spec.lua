---@module 'luassert'

describe("compose draft", function()
	local draft

	before_each(function()
		package.loaded["wiremux.ui.compose.draft"] = nil
		draft = require("wiremux.ui.compose.draft")
	end)

	it("saves edits without changing capture identity or results", function()
		local capture = {
			placeholder_capture = {
				enabled = true,
				results = { selection = "captured" },
			},
		}
		local state = draft.new("first", capture)

		draft.save(state, "edited")

		assert.are.equal(1, state.current_page)
		assert.are.equal("edited", draft.current(state).text)
		assert.are.equal(capture, draft.current(state).capture)
		assert.are.equal("captured", draft.current(state).capture.placeholder_capture.results.selection)
	end)

	it("keeps distinct captures for identical raw text", function()
		local first_capture = { source = "first" }
		local second_capture = { source = "second" }
		local state = draft.new("same", first_capture)
		draft.append(state, "same", second_capture)

		assert.are.equal(first_capture, state.pages[1].capture)
		assert.are.equal(second_capture, state.pages[2].capture)
		assert.are_not.equal(state.pages[1].capture, state.pages[2].capture)
	end)

	it("appends and selects a page with only its incoming capture", function()
		local first_capture = { value = "one" }
		local second_capture = { value = "two" }
		local state = draft.new("first", first_capture)
		draft.append(state, "second", second_capture)

		assert.are.equal(2, state.current_page)
		assert.are.equal("second", draft.current(state).text)
		assert.are.equal(second_capture, draft.current(state).capture)
		assert.are.equal(first_capture, state.pages[1].capture)
	end)

	it("replaces the complete draft and drops old capture references", function()
		local first_capture = { value = "one" }
		local second_capture = { value = "two" }
		local replacement_capture = { value = "replacement" }
		local state = draft.new("first", first_capture)
		draft.append(state, "second", second_capture)
		local old_pages = state.pages

		draft.replace(state, "replacement", replacement_capture)

		assert.are.equal(1, #state.pages)
		assert.are.equal(1, state.current_page)
		assert.are_not.equal(old_pages, state.pages)
		assert.are.same({ text = "replacement", capture = replacement_capture }, state.pages[1])
		assert.are_not.equal(first_capture, state.pages[1].capture)
		assert.are_not.equal(second_capture, state.pages[1].capture)
	end)

	it("wraps navigation without swapping page captures", function()
		local captures = { { page = 1 }, { page = 2 }, { page = 3 } }
		local state = draft.new("first", captures[1])
		draft.append(state, "second", captures[2])
		draft.append(state, "third", captures[3])

		assert.are.equal(1, draft.next(state))
		assert.are.equal(captures[1], draft.current(state).capture)
		assert.are.equal(3, draft.previous(state))
		assert.are.equal(captures[3], draft.current(state).capture)
		assert.are.equal(2, draft.previous(state))
		assert.are.equal(captures[2], draft.current(state).capture)
		for index, capture in ipairs(captures) do
			assert.are.equal(capture, state.pages[index].capture)
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
