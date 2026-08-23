---@module 'luassert'

local helpers = require("tests.helpers")
local send_helpers = require("tests.helpers_send")

local MODULES = {
	"wiremux.action.send.materialize",
	"wiremux.context",
}

describe("send materialization", function()
	local context
	local materialize

	before_each(function()
		helpers.clear(MODULES)
		context = require("wiremux.context")
		materialize = require("wiremux.action.send.materialize")
	end)

	after_each(function()
		context.configure()
		helpers.clear(MODULES)
	end)

	it("extends a direct capture without resolving again or changing whitespace", function()
		local resolver_calls = 0
		context.configure({
			direct_value = function()
				resolver_calls = resolver_calls + 1
				return "captured"
			end,
		})
		local raw_text = "\n  {direct_value}  \n"
		local capture = context.capture(raw_text)
		local stored = vim.deepcopy(capture)
		local materialize_calls = 0
		local context_materialize = context.materialize
		context.materialize = function(text, working_capture)
			materialize_calls = materialize_calls + 1
			return context_materialize(text, working_capture)
		end

		local payload, err = materialize.direct({
			raw_text = raw_text,
			placeholder_capture = capture,
		})

		context.materialize = context_materialize
		assert.is_nil(err)
		assert.are.equal("\n  captured  \n", payload)
		assert.are.equal(1, resolver_calls)
		assert.are.equal(1, materialize_calls)
		assert.are.same(stored, capture)
	end)

	it("routes direct and compose text through the same lookup-only materializer", function()
		local capture = { enabled = true, capture_set = {}, values = {} }
		local calls = {}
		local context_materialize = context.materialize
		context.materialize = function(text, working)
			table.insert(calls, { text = text, working = working })
			return context_materialize(text, working)
		end

		assert(materialize.direct({ raw_text = "direct", placeholder_capture = capture }))
		assert(materialize.compose({
			{ text = "compose", capture = { placeholder_capture = capture } },
		}))

		context.materialize = context_materialize
		assert.are.equal(2, #calls)
		assert.are.equal("direct", calls[1].text)
		assert.are.equal("compose", calls[2].text)
		assert.are_not.equal(capture, calls[1].working)
		assert.are_not.equal(capture, calls[2].working)
	end)

	it("previews stored and new values without mutating or retrying the page capture", function()
		local calls = { stored = 0, missing = 0, late = 0 }
		local stored_value = "stored"
		context.configure({
			stored = function()
				calls.stored = calls.stored + 1
				return stored_value
			end,
			missing = function()
				calls.missing = calls.missing + 1
				return nil
			end,
			late = function()
				calls.late = calls.late + 1
				return "late"
			end,
		})
		local capture = context.capture("{stored} {missing}")
		local original = vim.deepcopy(capture)
		local page_capture = { placeholder_capture = capture }
		stored_value = "changed"

		local stored = assert(materialize.preview_placeholder(page_capture, "stored"))
		local missing, missing_error = materialize.preview_placeholder(page_capture, "missing")
		local late = assert(materialize.preview_placeholder(page_capture, "late"))

		assert.are.equal("stored", stored)
		assert.is_nil(missing)
		assert.are.equal("placeholder_unavailable", missing_error.code)
		assert.are.equal("late", late)
		assert.are.same({ stored = 1, missing = 1, late = 1 }, calls)
		assert.are.same(original, capture)
	end)

	it("preserves page positions while trimming only trailing whitespace", function()
		local capture = { enabled = true, capture_set = {}, values = {} }
		local function page(text)
			return { text = text, capture = { placeholder_capture = capture } }
		end

		local payload = assert(materialize.compose({
			page("  first \n\t "),
			page(" \t"),
			page(""),
			page("last\n"),
		}))

		assert.are.equal("  first\n\n\n\n\n\nlast", payload)
	end)

	it("returns a page-numbered error for missing and malformed captures", function()
		local _, missing = materialize.compose({ { text = "draft" } })
		local _, malformed = materialize.compose({
			{ text = "valid", capture = { placeholder_capture = { enabled = true, capture_set = {}, values = {} } } },
			{ text = "invalid", capture = { placeholder_capture = { enabled = true } } },
		})

		assert.are.equal("compose_page_failed", missing.code)
		assert.are.equal(1, missing.page)
		assert.matches("page 1", missing.message)
		assert.are.equal("compose_page_failed", malformed.code)
		assert.are.equal(2, malformed.page)
		assert.matches("page 2", malformed.message)
	end)

	it("returns no partial payload and stops after the first page failure", function()
		local capture = { enabled = true, capture_set = {}, values = {} }
		local materialize_calls = 0
		local context_materialize = context.materialize
		context.materialize = function(text, working)
			materialize_calls = materialize_calls + 1
			return context_materialize(text, working)
		end

		local payload, err = materialize.compose({
			{ text = "first", capture = { placeholder_capture = capture } },
			{ text = "broken", capture = { placeholder_capture = { enabled = true } } },
			{ text = "never", capture = { placeholder_capture = capture } },
		})

		context.materialize = context_materialize
		assert.is_nil(payload)
		assert.are.equal(2, err.page)
		assert.are.equal(1, materialize_calls)
	end)

	it("returns structured direct materialization errors", function()
		local payload, err = materialize.direct({ raw_text = "draft" })

		assert.is_nil(payload)
		assert.are.equal("direct_failed", err.code)
		assert.matches("direct payload", err.message)
	end)
end)

describe("send materialization orchestration", function()
	local mocks

	before_each(function()
		mocks = send_helpers.setup()
	end)

	after_each(function()
		send_helpers.teardown()
	end)

	it("formats captured changes for the compose placeholder preview", function()
		local preview
		mocks.context.capture = function()
			return {
				enabled = true,
				capture_set = { changes = true },
				values = { changes = "diff --git a/file b/file" },
			}
		end
		mocks.compose.open = function(_, options)
			preview = { options.on_preview(options.capture, "changes") }
		end

		mocks.send.send({ value = "{changes}", compose = true })

		assert.are.same({ "diff --git a/file b/file", "diff" }, preview)
	end)

	it("queues exactly one delivery after successful synchronous confirmation", function()
		local confirming = false
		local confirmation_results = {}
		mocks.compose.open = function(_, options)
			confirming = true
			local pages = { { text = "edited", capture = options.capture } }
			table.insert(confirmation_results, options.on_confirm(pages))
			table.insert(confirmation_results, options.on_confirm(pages))
			confirming = false
		end
		local deliveries = 0
		mocks.backend.send = function(text)
			assert.is_false(confirming)
			assert.are.equal("edited", text)
			deliveries = deliveries + 1
		end
		mocks.action.run = function(_, callbacks)
			callbacks.on_targets({}, {})
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return deliveries > 0
		end)

		assert.are.same({ true, true }, confirmation_results)
		assert.are.equal(1, deliveries)
	end)

	it("preserves confirmation on a page error and performs no delivery", function()
		local confirmation_result
		local delivery_calls = 0
		local notification
		mocks.compose.open = function(_, options)
			confirmation_result = options.on_confirm({ { text = "broken" } })
		end
		mocks.action.run = function()
			delivery_calls = delivery_calls + 1
		end
		mocks.notify.error = function(message)
			notification = message
		end

		mocks.send.send({ value = "draft", compose = true })

		assert.is_false(confirmation_result)
		assert.are.equal(0, delivery_calls)
		assert.matches("page 1", notification)
	end)

	it("notifies delivery errors at the orchestration boundary", function()
		local notification
		mocks.backend = nil
		mocks.notify.error = function(message)
			notification = message
		end

		mocks.send.send("payload")

		assert.matches("no active backend", notification)
	end)

	it("treats target-picker cancellation after confirmation as no delivery", function()
		local action_called = false
		local backend_calls = 0
		mocks.compose.open = function(_, options)
			assert.is_true(options.on_confirm({ { text = "edited", capture = options.capture } }))
		end
		mocks.action.run = function()
			action_called = true
			-- Target picker cancellation dispatches no delivery callback.
		end
		mocks.backend.send = function()
			backend_calls = backend_calls + 1
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return action_called
		end)

		assert.is_true(action_called)
		assert.are.equal(0, backend_calls)
	end)
end)
