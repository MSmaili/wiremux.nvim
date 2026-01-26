---@module 'luassert'

describe("action", function()
	local action, backend, resolver, config, picker, notify

	before_each(function()
		-- Clear modules
		package.loaded["wiremux.core.action"] = nil
		package.loaded["wiremux.backend.tmux"] = nil
		package.loaded["wiremux.core.resolver"] = nil
		package.loaded["wiremux.config"] = nil
		package.loaded["wiremux.picker"] = nil
		package.loaded["wiremux.utils.notify"] = nil

		-- Mock backend
		backend = {
			state = {
				get = function()
					return { instances = {}, last_used_target_id = nil }
				end,
			},
			create = function(name, def, state)
				return { id = "%1", kind = "pane", target = name }
			end,
		}

		-- Mock resolver
		resolver = {
			resolve = function()
				return { kind = "targets", targets = {} }
			end,
		}

		-- Mock config
		config = {
			opts = {
				targets = { definitions = {} },
			},
		}

		-- Mock picker
		picker = {
			select = function() end,
		}

		-- Mock notify
		notify = {
			warn = function() end,
			error = function() end,
		}

		package.loaded["wiremux.backend.tmux"] = backend
		package.loaded["wiremux.core.resolver"] = resolver
		package.loaded["wiremux.config"] = config
		package.loaded["wiremux.picker"] = picker
		package.loaded["wiremux.utils.notify"] = notify

		action = require("wiremux.core.action")
	end)

	describe("run with targets result", function()
		it("executes callback with targets", function()
			local executed = false
			local received_targets

			resolver.resolve = function()
				return {
					kind = "targets",
					targets = {
						{ id = "%1", kind = "pane", target = "test" },
					},
				}
			end

			action.run({ prompt = "Test", behavior = "all" }, function(targets, state)
				executed = true
				received_targets = targets
			end)

			assert.is_true(executed)
			assert.are.equal(1, #received_targets)
			assert.are.equal("%1", received_targets[1].id)
		end)
	end)

	describe("run with pick result", function()
		it("shows picker when result is pick", function()
			local picker_shown = false

			resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "instance", instance = { id = "%1" }, label = "test" },
					},
				}
			end

			picker.select = function(items, opts, callback)
				picker_shown = true
				assert.are.equal(1, #items)
				assert.are.equal("Test Prompt", opts.prompt)
			end

			action.run({ prompt = "Test Prompt", behavior = "pick" }, function() end)

			assert.is_true(picker_shown)
		end)

		it("executes callback when instance is picked", function()
			local executed = false

			resolver.resolve = function()
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

			picker.select = function(items, opts, callback)
				-- Simulate user picking first item
				callback(items[1])
			end

			action.run({ prompt = "Test", behavior = "pick" }, function(targets, state)
				executed = true
				assert.are.equal(1, #targets)
				assert.are.equal("%1", targets[1].id)
			end)

			assert.is_true(executed)
		end)

		it("creates target when definition is picked", function()
			local create_called = false
			local executed = false

			resolver.resolve = function()
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

			backend.create = function(name, def, state)
				create_called = true
				assert.are.equal("server", name)
				return { id = "%1", kind = "pane", target = "server" }
			end

			picker.select = function(items, opts, callback)
				callback(items[1])
			end

			action.run({ prompt = "Test", behavior = "pick" }, function(targets, state)
				executed = true
				assert.are.equal("%1", targets[1].id)
			end)

			assert.is_true(create_called)
			assert.is_true(executed)
		end)

		it("handles create failure gracefully", function()
			local error_shown = false

			resolver.resolve = function()
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

			backend.create = function()
				return nil -- Simulate failure
			end

			notify.error = function(msg)
				error_shown = true
				assert.matches("failed to create", msg)
			end

			picker.select = function(items, opts, callback)
				callback(items[1])
			end

			action.run({ prompt = "Test", behavior = "pick" }, function()
				error("should not execute")
			end)

			assert.is_true(error_shown)
		end)

		it("handles picker cancellation", function()
			resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "instance", instance = { id = "%1" }, label = "test" },
					},
				}
			end

			picker.select = function(items, opts, callback)
				callback(nil) -- User cancelled
			end

			action.run({ prompt = "Test", behavior = "pick" }, function()
				error("should not execute when cancelled")
			end)

			-- Test passes if no error thrown
		end)
	end)

	describe("run with no targets", function()
		it("shows warning when no targets available", function()
			local warned = false

			resolver.resolve = function()
				return { kind = "pick", items = {} }
			end

			notify.warn = function(msg)
				warned = true
				assert.matches("no targets", msg)
			end

			action.run({ prompt = "Test", behavior = "pick" }, function()
				error("should not execute")
			end)

			assert.is_true(warned)
		end)
	end)
end)
