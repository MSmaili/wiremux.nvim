---@module 'luassert'

local helpers = require("tests.helpers_send")

describe("send text string", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("calls action.run to resolve targets", function()
		local run_called = false

		mocks.action.run = function(opts, callbacks)
			run_called = true
			assert.are.equal("Send to", opts.prompt)
			assert.are.equal("pick", opts.behavior)
		end

		mocks.send.send("hello world")

		assert.is_true(run_called)
	end)

	it("sends text to existing targets", function()
		local send_called = false
		local received_text
		local received_targets

		mocks.backend.send = function(text, targets, opts, state)
			send_called = true
			received_text = text
			received_targets = targets
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("test command")

		assert.is_true(send_called)
		assert.are.equal("test command", received_text)
		assert.are.equal(1, #received_targets)
	end)
end)
