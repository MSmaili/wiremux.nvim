---@module 'luassert'

local send_helpers = require("tests.helpers_send")

local ORIGIN = { bufnr = 1, path = "/source.lua", row = 1, col = 0, selection = "", line = "" }

describe("send payload assembly", function()
	local mocks

	before_each(function()
		mocks = send_helpers.setup()
	end)

	after_each(function()
		send_helpers.teardown()
	end)

	it("resolves a direct send one time against the call origin", function()
		local calls = {}
		local history_calls = 0
		mocks.history.add = function()
			history_calls = history_calls + 1
			return true
		end
		mocks.context.resolve = function(text, origin)
			table.insert(calls, { text = text, origin = origin })
			return "resolved"
		end
		local delivered
		mocks.backend.send = function(text)
			delivered = text
		end

		mocks.send.send("\n  {value}  \n")

		assert.are.equal(1, #calls)
		assert.are.equal("\n  {value}  \n", calls[1].text)
		assert.are.same(ORIGIN, calls[1].origin)
		assert.are.equal("resolved", delivered)
		assert.are.equal(0, history_calls)
	end)

	it("keeps text literal for a direct send with placeholders disabled", function()
		mocks.context.resolve = function()
			error("resolve must not run")
		end
		local delivered
		mocks.backend.send = function(text)
			delivered = text
		end

		mocks.send.send({ value = "literal {file}", placeholders = false })

		assert.are.equal("literal {file}", delivered)
	end)

	it("resolves each compose page against its own origin", function()
		local calls = {}
		mocks.context.resolve = function(text, origin)
			table.insert(calls, { text = text, origin = origin })
			return text:upper()
		end
		local delivered
		mocks.backend.send = function(text)
			delivered = text
		end
		local second = vim.tbl_extend("force", {}, ORIGIN, { path = "/other.lua", row = 9 })
		mocks.compose.open = function(_, options)
			options.on_confirm({
				{ text = "first", source = options.source },
				{ text = "second", source = { origin = second, resolve = true } },
			})
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return delivered ~= nil
		end)

		assert.are.equal(2, #calls)
		assert.are.same(ORIGIN, calls[1].origin)
		assert.are.same(second, calls[2].origin)
		assert.are.equal("FIRST\n\nSECOND", delivered)
	end)

	it("records the resolved compose payload before delivery", function()
		mocks.context.resolve = function(text)
			return text:upper()
		end
		local calls = {}
		mocks.history.add = function(payload)
			table.insert(calls, { "history", payload })
			return true
		end
		mocks.backend.send = function(payload)
			table.insert(calls, { "delivery", payload })
		end
		mocks.compose.open = function(_, options)
			options.on_confirm({
				{ text = "first", source = options.source },
				{ text = "second", source = options.source },
			})
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return #calls == 2
		end)

		assert.are.same({ "history", "FIRST\n\nSECOND" }, calls[1])
		assert.are.same({ "delivery", "FIRST\n\nSECOND" }, calls[2])
	end)

	it("still delivers when compose history cannot be saved", function()
		mocks.history.add = function()
			error("disk full")
		end
		local warning
		mocks.notify.warn = function(message)
			warning = message
		end
		local delivered
		mocks.backend.send = function(payload)
			delivered = payload
		end
		mocks.compose.open = function(_, options)
			options.on_confirm({ { text = "draft", source = options.source } })
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return delivered ~= nil
		end)

		assert.are.equal("draft", delivered)
		assert.matches("disk full", warning)
	end)

	it("keeps a page literal when its source disables resolution", function()
		local resolved = 0
		mocks.context.resolve = function(text)
			resolved = resolved + 1
			return text
		end
		local delivered
		mocks.backend.send = function(text)
			delivered = text
		end
		mocks.compose.open = function(_, options)
			options.on_confirm({
				{ text = "kept {file}", source = { origin = ORIGIN, resolve = false } },
			})
		end

		mocks.send.send({ value = "draft", compose = true, placeholders = false })
		vim.wait(100, function()
			return delivered ~= nil
		end)

		assert.are.equal(0, resolved)
		assert.are.equal("kept {file}", delivered)
	end)

	it("preserves page positions while trimming only trailing whitespace", function()
		local delivered
		mocks.backend.send = function(text)
			delivered = text
		end
		local function page(text)
			return { text = text, source = { origin = ORIGIN, resolve = true } }
		end
		mocks.compose.open = function(_, options)
			options.on_confirm({ page("  first \n\t "), page(" \t"), page(""), page("last\n") })
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return delivered ~= nil
		end)

		assert.are.equal("  first\n\n\n\n\n\nlast", delivered)
	end)

	it("returns a page-numbered error for a malformed page and delivers nothing", function()
		local notification
		local delivery_calls = 0
		local confirmation_result
		mocks.notify.error = function(message)
			notification = message
		end
		mocks.action.run = function()
			delivery_calls = delivery_calls + 1
		end
		mocks.compose.open = function(_, options)
			confirmation_result = options.on_confirm({ { text = "draft" } })
		end

		mocks.send.send({ value = "draft", compose = true })

		assert.is_false(confirmation_result)
		assert.are.equal(0, delivery_calls)
		assert.matches("page 1", notification)
	end)

	it("stops at the first bad page and returns no partial payload", function()
		local resolved = 0
		mocks.context.resolve = function(text)
			resolved = resolved + 1
			return text
		end
		local notification
		mocks.notify.error = function(message)
			notification = message
		end
		mocks.compose.open = function(_, options)
			options.on_confirm({
				{ text = "first", source = { origin = ORIGIN, resolve = true } },
				{ text = "broken" },
				{ text = "never", source = { origin = ORIGIN, resolve = true } },
			})
		end

		mocks.send.send({ value = "draft", compose = true })

		assert.are.equal(1, resolved)
		assert.matches("page 2", notification)
	end)
end)

describe("send placeholder preview", function()
	local mocks

	before_each(function()
		mocks = send_helpers.setup()
	end)

	after_each(function()
		send_helpers.teardown()
	end)

	---@param name string
	---@return table preview
	local function preview_for(name)
		local preview
		mocks.compose.open = function(_, options)
			preview = { options.on_preview(options.source, name) }
		end
		mocks.send.send({ value = "{" .. name .. "}", compose = true })
		return assert(preview)
	end

	it("formats changes as diff syntax and passes the page origin", function()
		local received
		mocks.context.get = function(_, origin)
			received = origin
			return "diff --git a/file b/file"
		end

		assert.are.same({ "diff --git a/file b/file", "diff" }, preview_for("changes"))
		assert.are.same(ORIGIN, received)
	end)

	it("formats other names as text", function()
		mocks.context.get = function()
			return "/source.lua"
		end

		assert.are.same({ "/source.lua", "text" }, preview_for("file"))
	end)

	it("reports an empty value", function()
		mocks.context.get = function()
			return ""
		end

		assert.are.same({ "(empty)", "text" }, preview_for("selection"))
	end)

	it("reports an unavailable value", function()
		mocks.context.get = function()
			return nil
		end

		local preview = preview_for("missing")

		assert.matches("No value is available for {missing}", preview[1])
		assert.are.equal("text", preview[2])
	end)

	it("reports disabled replacement for a literal page", function()
		mocks.context.get = function()
			error("resolver must not run")
		end
		local preview
		mocks.compose.open = function(_, options)
			preview = { options.on_preview(options.source, "file") }
		end

		mocks.send.send({ value = "{file}", compose = true, placeholders = false })

		assert.matches("disabled", assert(preview)[1])
	end)
end)

describe("send delivery orchestration", function()
	local mocks

	before_each(function()
		mocks = send_helpers.setup()
	end)

	after_each(function()
		send_helpers.teardown()
	end)

	it("queues delivery outside synchronous confirmation", function()
		local confirming = false
		local confirmation_result
		mocks.compose.open = function(_, options)
			confirming = true
			confirmation_result = options.on_confirm({ { text = "edited", source = options.source } })
			confirming = false
		end
		local deliveries = 0
		mocks.backend.send = function(text)
			assert.is_false(confirming)
			assert.are.equal("edited", text)
			deliveries = deliveries + 1
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return deliveries > 0
		end)

		assert.is_true(confirmation_result)
		assert.are.equal(1, deliveries)
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
			assert.is_true(options.on_confirm({ { text = "edited", source = options.source } }))
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
