---@module 'luassert'

local helpers = require("tests.helpers_send")

describe("send to new target without cmd", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("uses sent text as cmd when target has no cmd", function()
		local create_def
		local send_called = false

		mocks.backend.create = function(name, def, state)
			create_def = def
			return { id = "%1", kind = "pane", target = name }
		end

		mocks.backend.send = function()
			send_called = true
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_definition("quick", { shell = false }, {})
		end

		mocks.send.send("go test ./...")

		assert.are.equal("go test ./...", create_def.cmd)
		assert.is_false(send_called)
	end)

	it("respects shell setting when using sent text as cmd", function()
		local create_def

		mocks.backend.create = function(name, def, state)
			create_def = def
			return { id = "%1", kind = "pane", target = name }
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_definition("quick", { shell = false }, {})
		end

		mocks.send.send("npm run start")

		assert.are.equal(false, create_def.shell)
	end)

	it("sends text normally when target has its own cmd", function()
		local create_def
		local send_text
		local send_called = false

		mocks.backend.create = function(name, def, state)
			create_def = def
			return { id = "%1", kind = "pane", target = name }
		end

		mocks.backend.send = function(text, targets, opts, state)
			send_called = true
			send_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_definition("ai", { cmd = "opencode", shell = false }, {})
		end

		mocks.send.send("explain this code")

		assert.are.equal("opencode", create_def.cmd)
		assert.is_true(send_called)
		assert.are.equal("explain this code", send_text)
	end)

	it("preserves other target properties when using sent text as cmd", function()
		local create_def

		mocks.backend.create = function(name, def, state)
			create_def = def
			return { id = "%1", kind = "pane", target = name }
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_definition("quick", {
				shell = false,
				split = "horizontal",
				kind = "pane",
			}, {})
		end

		mocks.send.send("go test ./...")

		assert.are.equal("go test ./...", create_def.cmd)
		assert.are.equal(false, create_def.shell)
		assert.are.equal("horizontal", create_def.split)
		assert.are.equal("pane", create_def.kind)
	end)
end)

describe("send with options", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("passes options through to underlying functions", function()
		local send_opts, received_behavior, received_filter

		mocks.backend.send = function(text, targets, opts, state)
			send_opts = opts
		end

		mocks.action.run = function(opts, callbacks)
			received_behavior = opts.behavior
			received_filter = opts.filter
			if callbacks.on_targets then
				callbacks.on_targets({ { id = "%1", kind = "pane", target = "test" } }, {})
			end
		end

		local my_filter = { instances = function() return true end }
		mocks.send.send("test", { 
			focus = true, 
			behavior = "last",
			filter = my_filter 
		})

		assert.is_true(send_opts.focus)
		assert.are.equal("last", received_behavior)
		assert.are.equal(my_filter, received_filter)
	end)
end)

describe("context expansion", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("expands placeholders in text", function()
		local expanded = "expanded text"

		mocks.context.expand = function(text)
			assert.are.equal("{file}", text)
			return expanded
		end

		local received_text

		mocks.backend.send = function(text, targets, opts, state)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send("{file}")

		assert.are.equal(expanded, received_text)
	end)

	it("expands placeholders in SendItem value", function()
		local expanded = "expanded"

		mocks.context.expand = function(text)
			return expanded
		end

		local received_text

		mocks.backend.send = function(text, targets, opts, state)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send({ value = "{placeholder}" })

		assert.are.equal(expanded, received_text)
	end)

	it("handles expansion error gracefully", function()
		local error_shown = false

		mocks.context.expand = function()
			error("invalid placeholder")
		end

		mocks.notify.error = function()
			error_shown = true
		end

		mocks.send.send("{invalid}")

		assert.is_true(error_shown)
	end)
end)
