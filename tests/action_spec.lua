---@module 'luassert'

local helpers = require("tests.helpers_action")

describe("action", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	after_each(function()
		helpers.teardown()
	end)

	describe("run with targets result", function()
		it("executes callback with targets", function()
			local executed = false
			local received_targets

			mocks.resolver.resolve = function()
				return {
					kind = "targets",
					targets = {
						{ id = "%1", kind = "pane", target = "test" },
					},
				}
			end

			mocks.action.run({ prompt = "Test", behavior = "all" }, {
				on_targets = function(targets, state)
					executed = true
					received_targets = targets
				end,
			})

			assert.is_true(executed)
			assert.are.equal(1, #received_targets)
			assert.are.equal("%1", received_targets[1].id)
		end)
	end)

	describe("run with pick result", function()
		it("shows picker when result is pick", function()
			local picker_shown = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "instance", instance = { id = "%1" }, label = "test" },
					},
				}
			end

			mocks.picker.select = function(items, opts, callback)
				picker_shown = true
				assert.are.equal(1, #items)
				assert.are.equal("Test Prompt", opts.prompt)
			end

			mocks.action.run({ prompt = "Test Prompt", behavior = "pick" }, {
				on_targets = function() end,
			})

			assert.is_true(picker_shown)
		end)

		it("executes callback when instance is picked", function()
			local executed = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{
							type = "instance",
							instance = { id = "%1", kind = "pane", target = "test" },
							label = "test",
						},
					},
				}
			end

			mocks.picker.select = function(items, opts, callback)
				-- Simulate user picking first item
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_targets = function(targets, state)
					executed = true
					assert.are.equal(1, #targets)
					assert.are.equal("%1", targets[1].id)
				end,
			})

			assert.is_true(executed)
		end)

		it("creates target when definition is picked", function()
			local create_called = false
			local executed = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{
							type = "definition",
							target = "server",
							def = { kind = "pane" },
							label = "server",
						},
					},
				}
			end

			mocks.backend.create = function(name, def, state)
				create_called = true
				assert.are.equal("server", name)
				return { id = "%1", kind = "pane", target = "server" }
			end

			mocks.picker.select = function(items, opts, callback)
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_definition = function(name, def, state)
					executed = true
					assert.are.equal("server", name)
					local inst = mocks.backend.create(name, def, state)
					assert.are.equal("%1", inst.id)
				end,
			})

			assert.is_true(create_called)
			assert.is_true(executed)
		end)

		it("handles create failure gracefully", function()
			local error_shown = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{
							type = "definition",
							target = "server",
							def = { kind = "pane" },
							label = "server",
						},
					},
				}
			end

			mocks.backend.create = function()
				return nil -- Simulate failure
			end

			mocks.notify.error = function(msg)
				error_shown = true
				assert.matches("failed to create", msg)
			end

			mocks.picker.select = function(items, opts, callback)
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_definition = function(name, def, state)
					local inst = mocks.backend.create(name, def, state)
					if not inst then
						mocks.notify.error("failed to create target: " .. name)
					end
				end,
			})

			assert.is_true(error_shown)
		end)

		it("handles picker cancellation", function()
			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "instance", instance = { id = "%1" }, label = "test" },
					},
					has_instances = true,
					has_definitions = false,
				}
			end

			mocks.picker.select = function(items, opts, callback)
				callback(nil) -- User cancelled
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_targets = function()
					error("should not execute when cancelled")
				end,
			})

			-- Test passes if no error thrown
		end)
	end)

	describe("run with no targets", function()
		it("shows warning when no targets available", function()
			local warned = false

			mocks.resolver.resolve = function()
				return { kind = "pick", items = {} }
			end

			mocks.notify.warn = function(msg)
				warned = true
				assert.matches("No targets", msg)
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_targets = function()
					error("should not execute")
				end,
			})

			assert.is_true(warned)
		end)
	end)
end)
