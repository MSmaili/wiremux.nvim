---@module 'luassert'

local helpers = require("tests.helpers_send")

describe("send with input placeholders", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("prompts user and sends expanded text", function()
		local received_text

		mocks.input.find = function(text)
			return { "input:Branch" }
		end
		mocks.input.resolve = function(keys, on_done)
			on_done({ ["input:Branch"] = "develop" })
		end
		mocks.input.replace = function(text, values)
			return text:gsub("{input:Branch}", values["input:Branch"])
		end

		mocks.context.expand = function(text)
			return text
		end

		mocks.backend.send = function(text)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("git checkout {input:Branch}")

		assert.are.equal("git checkout develop", received_text)
	end)

	it("aborts send when user cancels input", function()
		local send_called = false

		mocks.input.find = function()
			return { "input" }
		end
		mocks.input.resolve = function(keys, on_done)
			on_done(nil)
		end

		mocks.backend.send = function()
			send_called = true
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("echo {input}")

		assert.is_false(send_called)
	end)

	it("expands sync placeholders before input resolution", function()
		local received_text
		local expand_order = {}

		mocks.context.expand = function(text)
			table.insert(expand_order, "expand")
			return text:gsub("{file}", "/path/to/file.lua")
		end

		mocks.input.find = function(text)
			table.insert(expand_order, "find")
			return { "input:Name" }
		end
		mocks.input.resolve = function(keys, on_done)
			table.insert(expand_order, "resolve")
			on_done({ ["input:Name"] = "world" })
		end
		mocks.input.replace = function(text, values)
			return text:gsub("{input:Name}", values["input:Name"])
		end

		mocks.backend.send = function(text)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("echo {input:Name} in {file}")

		assert.are.equal("echo world in /path/to/file.lua", received_text)
		-- Verify ordering: expand runs before input find/resolve
		assert.are.same({ "expand", "find", "resolve" }, expand_order)
	end)

	it("skips input resolution for text without input placeholders", function()
		local resolve_called = false

		mocks.input.resolve = function()
			resolve_called = true
		end

		local received_text

		mocks.backend.send = function(text)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("plain text")

		assert.is_false(resolve_called)
		assert.are.equal("plain text", received_text)
	end)

	it("preserves {selection} when mixed with {input}", function()
		local received_text

		-- Simulate: expand resolves {selection} but leaves {input:Name} untouched
		-- Bare {input} is skipped explicitly in context.expand
		mocks.context.expand = function(text)
			return text:gsub("{selection}", "selected text")
		end

		mocks.input.find = function(text)
			return { "input:Name" }
		end
		mocks.input.resolve = function(keys, on_done)
			on_done({ ["input:Name"] = "value" })
		end
		mocks.input.replace = function(text, values)
			return text:gsub("{input:Name}", values["input:Name"])
		end

		mocks.backend.send = function(text)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("echo {selection} {input:Name}")

		assert.are.equal("echo selected text value", received_text)
	end)
end)
