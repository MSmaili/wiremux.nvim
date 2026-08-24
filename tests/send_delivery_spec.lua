---@module 'luassert'

local helpers = require("tests.helpers")

local MODULES = {
	"wiremux.action.send.delivery",
	"wiremux.backend",
	"wiremux.core.action",
}

describe("send delivery", function()
	local action
	local backend
	local delivery

	before_each(function()
		helpers.clear(MODULES)
		action = { run = function() end }
		backend = helpers.mock_backend({ send = function() end })
		helpers.register({
			["wiremux.backend"] = {
				get = function()
					return backend
				end,
			},
			["wiremux.core.action"] = action,
		})
		delivery = require("wiremux.action.send.delivery")
	end)

	after_each(function()
		helpers.clear(MODULES)
	end)

	it("sends to existing targets with prepared selection and backend options", function()
		local filter = {
			instances = function()
				return true
			end,
		}
		local target = { id = "%1", kind = "pane", target = "terminal" }
		local state = { origin_pane_id = "%0" }
		local selection_options
		local sent
		action.run = function(options, callbacks)
			selection_options = options
			callbacks.on_targets({ target }, state)
		end
		backend.send = function(payload, targets, options, received_state)
			sent = {
				payload = payload,
				targets = targets,
				options = options,
				state = received_state,
			}
		end

		local started, err = delivery.send("payload", {
			focus = true,
			behavior = "last",
			mode = "instances",
			target = "terminal",
			filter = filter,
			pre_keys = { "C-c" },
			post_keys = { "Enter" },
		}, "Target Title")

		assert.is_true(started)
		assert.is_nil(err)
		assert.are.same({
			prompt = "Send to",
			behavior = "last",
			mode = "instances",
			target = "terminal",
			filter = filter,
		}, selection_options)
		assert.are.equal("payload", sent.payload)
		assert.are.same({ target }, sent.targets)
		assert.are.same({ focus = true, pre_keys = { "C-c" }, post_keys = { "Enter" } }, sent.options)
		assert.are.equal(state, sent.state)
	end)

	it("uses the payload as the command for definitions without a command", function()
		local created
		local send_calls = 0
		action.run = function(_, callbacks)
			callbacks.on_definition("quick", { shell = false, kind = "pane" }, { state = true })
		end
		backend.create = function(name, def, state)
			created = { name = name, def = def, state = state }
			return { id = "%1" }
		end
		backend.send = function()
			send_calls = send_calls + 1
		end

		local started = delivery.send("go test ./...", {
			behavior = "pick",
			mode = "auto",
		}, "Tests")

		assert.is_true(started)
		assert.are.equal("quick", created.name)
		assert.are.equal("go test ./...", created.def.cmd)
		assert.are.equal("Tests", created.def.title)
		assert.is_false(created.def.shell)
		assert.are.equal("pane", created.def.kind)
		assert.are.same({ state = true }, created.state)
		assert.are.equal(0, send_calls)
	end)

	it("waits for definitions with their own command before sending", function()
		local instance = { id = "%2", kind = "pane", target = "assistant" }
		local created_def
		local ready_options
		local ready_callback
		local sends = {}
		action.run = function(_, callbacks)
			callbacks.on_definition("assistant", {
				cmd = "opencode",
				shell = false,
				startup_timeout = 900,
			}, {})
		end
		backend.create = function(_, def)
			created_def = def
			return instance
		end
		backend.wait_for_ready = function(received_instance, options, callback)
			assert.are.equal(instance, received_instance)
			ready_options = options
			ready_callback = callback
		end
		backend.send = function(...)
			table.insert(sends, { ... })
		end

		local started = delivery.send("review this", {
			focus = false,
			behavior = "pick",
			mode = "definitions",
			pre_keys = { "i" },
			post_keys = { "Escape" },
		}, "Assistant")
		ready_callback()

		assert.is_true(started)
		assert.are.equal("opencode", created_def.cmd)
		assert.are.equal("Assistant", created_def.title)
		assert.are.same({ timeout_ms = 900 }, ready_options)
		assert.are.equal(1, #sends)
		assert.are.equal("review this", sends[1][1])
		assert.are.same({ instance }, sends[1][2])
		assert.are.same({ focus = false, pre_keys = { "i" }, post_keys = { "Escape" } }, sends[1][3])
	end)

	it("treats target-picker cancellation as a successful no-op", function()
		local sends = 0
		action.run = function()
			-- Picker cancelled: no callback is dispatched.
		end
		backend.send = function()
			sends = sends + 1
		end

		local started, err = delivery.send("payload", { behavior = "pick", mode = "auto" })

		assert.is_true(started)
		assert.is_nil(err)
		assert.are.equal(0, sends)
	end)

	it("reports backend and invocation failures", function()
		package.loaded["wiremux.backend"].get = function()
			return nil
		end
		local started, unavailable = delivery.send("payload", { behavior = "pick", mode = "auto" })

		package.loaded["wiremux.backend"].get = function()
			return backend
		end
		action.run = function()
			error("selection failed")
		end
		local invoked, failed = delivery.send("payload", { behavior = "pick", mode = "auto" })

		assert.is_false(started)
		assert.matches("no active backend", unavailable)
		assert.is_false(invoked)
		assert.matches("selection failed", failed)
	end)
end)
