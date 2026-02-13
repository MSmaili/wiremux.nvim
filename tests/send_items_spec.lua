---@module 'luassert'

local helpers = require("tests.helpers_send")

describe("send single item", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("handles SendItem table", function()
		local run_called = false

		mocks.action.run = function(opts, callbacks)
			run_called = true
		end

		mocks.send.send({
			value = "npm test",
			label = "Run tests",
		})

		assert.is_true(run_called)
	end)

	it("uses visible field to filter items", function()
		local picker_items = {}

		mocks.picker.select = function(items, opts, callback)
			picker_items = items
		end

		mocks.action.run = function()
			return { kind = "pick", items = {} }
		end

		mocks.send.send({
			{
				value = "visible item",
				visible = true,
			},
			{
				value = "hidden item",
				visible = false,
			},
			{
				value = "default visible",
			},
		})

		assert.are.equal(2, #picker_items)
	end)

	it("calls visible function and filters based on return value", function()
		local picker_items = {}
		local fn_called = false

		mocks.picker.select = function(items, opts, callback)
			picker_items = items
		end

		-- Test visible returns true
		mocks.send.send({
			{ value = "shown", visible = function() fn_called = true return true end },
			{ value = "hidden", visible = function() return false end },
		})

		assert.is_true(fn_called)
		assert.are.equal(1, #picker_items)
		assert.are.equal("shown", picker_items[1].value.value)
	end)

	it("uses submit option from item", function()
		local send_opts

		mocks.backend.send = function(text, targets, opts, state)
			send_opts = opts
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send({
			value = "go test ./...",
			submit = true,
		})

		assert.is_true(send_opts.submit)
	end)

	it("falls back to config submit option", function()
		local send_opts

		mocks.backend.send = function(text, targets, opts, state)
			send_opts = opts
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.config.opts.actions.send.submit = true
		mocks.send.send({ value = "npm test" })

		assert.is_true(send_opts.submit)
	end)
end)

describe("send list of items", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("shows picker when sending array of items", function()
		local picker_shown = false

		mocks.picker.select = function(items, opts, callback)
			picker_shown = true
			assert.are.equal(3, #items)
		end

		mocks.send.send({
			{ value = "test1" },
			{ value = "test2" },
			{ value = "test3" },
		})

		assert.is_true(picker_shown)
	end)

	it("uses label or value for display", function()
		local picker_items = {}

		mocks.picker.select = function(items, opts, callback)
			picker_items = items
		end

		mocks.send.send({
			{ value = "cmd1", label = "Custom Label" },
			{ value = "cmd2" },
		})

		assert.are.equal("Custom Label", picker_items[1].label)
		assert.are.equal("cmd2", picker_items[2].label)
	end)

	it("sends selected item to target", function()
		local send_called = false
		local received_text

		mocks.backend.send = function(text, targets, opts, state)
			send_called = true
			received_text = text
		end

		mocks.picker.select = function(items, opts, callback)
			callback(items[2])
		end

		mocks.send.send({
			{ value = "first" },
			{ value = "selected" },
		})

		assert.is_true(send_called)
		assert.are.equal("selected", received_text)
	end)

	it("handles picker cancellation", function()
		local send_called = false

		mocks.backend.send = function()
			send_called = true
		end

		mocks.picker.select = function(items, opts, callback)
			callback(nil)
		end

		mocks.send.send({
			{ value = "item1" },
			{ value = "item2" },
		})

		assert.is_false(send_called)
	end)

	it("warns when all items are hidden", function()
		local warned = false
		local warning_msg

		mocks.notify.warn = function(msg)
			warned = true
			warning_msg = msg
		end

		mocks.send.send({
			{ value = "hidden1", visible = false },
			{ value = "hidden2", visible = false },
		})

		assert.is_true(warned)
		assert.matches("No items", warning_msg)
	end)
end)
