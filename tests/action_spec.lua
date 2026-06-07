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

	describe("adopt", function()
		it("shows all current-session panes", function()
			local adopted

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane" },
						{ session_id = "$1", id = "%1", target = "server", kind = "pane", running_command = "zsh" },
						{ session_id = "$2", id = "%2", target = "other", kind = "pane" },
					},
					panes = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane", window_index = 1, pane_index = 0 },
						{
							session_id = "$1",
							id = "%1",
							target = "server",
							kind = "pane",
							window_index = 1,
							pane_index = 1,
							running_command = "zsh",
						},
						{
							session_id = "$1",
							id = "%3",
							kind = "pane",
							window_index = 2,
							pane_index = 0,
							running_command = "fish",
						},
						{ session_id = "$2", id = "%2", target = "other", kind = "pane", window_index = 1, pane_index = 0 },
					},
				}
			end

			mocks.backend.adopt = function(target)
				adopted = target
				return true
			end

			mocks.picker.select = function(items, opts, callback)
				assert.are.equal("Adopt target", opts.prompt)
				assert.are.equal(2, #items)
				assert.are.equal("%1", items[1].id)
				assert.are.equal("%3", items[2].id)
				assert.matches("server%s+%%1%s+1:1%s+zsh", opts.format_item(items[1]))
				assert.matches("%(unmanaged%)%s+%%3%s+2:0%s+fish", opts.format_item(items[2]))
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt()

			assert.are.equal("%1", adopted.id)
		end)

		it("applies an optional local instance filter", function()
			local adopted

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%1", target = "server", kind = "pane" },
						{ session_id = "$1", id = "%2", target = "claude", kind = "pane" },
					},
				}
			end

			mocks.backend.adopt = function(target)
				adopted = target
				return true
			end

			mocks.picker.select = function(items, _, callback)
				assert.are.equal(1, #items)
				assert.are.equal("%2", items[1].id)
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt({
				filter = {
					instances = function(inst)
						return inst.target == "claude"
					end,
				},
			})

			assert.are.equal("%2", adopted.id)
		end)

		it("lets a local filter choose cross-session and unmanaged panes", function()
			local adopted
			local adopt_opts

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%1", target = "server", kind = "pane" },
					},
					panes = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane" },
						{ session_id = "$1", id = "%1", target = "server", kind = "pane" },
						{ session_id = "$2", id = "%2", target = "remote", kind = "pane" },
						{ session_id = "$2", id = "%3", kind = "pane", running_command = "zsh" },
					},
				}
			end

			mocks.backend.adopt = function(target, _, opts)
				adopted = target
				adopt_opts = opts
				return true
			end

			mocks.picker.select = function(items, opts, callback)
				assert.are.equal(3, #items)
				assert.are.equal("%1", items[1].id)
				assert.are.equal("%2", items[2].id)
				assert.are.equal("%3", items[3].id)
				assert.matches("%(unmanaged%)%s+%%3%s+%-%s+zsh", opts.format_item(items[3]))
				callback(items[3])
			end

			require("wiremux.action.adopt").adopt({
				target = "terminal",
				filter = {
					instances = function()
						return true
					end,
				},
			})

			assert.are.equal("%3", adopted.id)
			assert.are.equal("terminal", adopt_opts.target)
		end)

		it("uses an optional local item formatter", function()
			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					panes = {
						{ session_id = "$1", id = "%1", target = "server", kind = "pane", running_command = "zsh" },
					},
					instances = {},
				}
			end

			mocks.backend.adopt = function()
				return true
			end

			mocks.picker.select = function(items, opts, callback)
				assert.are.equal("server:%1:$1", opts.format_item(items[1]))
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt({
				format_item = function(inst, state)
					return string.format("%s:%s:%s", inst.target, inst.id, state.session_id)
				end,
			})
		end)

		it("generates a target name when adopting unmanaged panes", function()
			local adopted
			local adopt_opts

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {},
					panes = {
						{ session_id = "$1", id = "%1", kind = "pane" },
					},
				}
			end

			mocks.backend.adopt = function(target, _, opts)
				adopted = target
				adopt_opts = opts
				return true
			end

			mocks.picker.select = function(items, _, callback)
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt()

			assert.are.equal("%1", adopted.id)
			assert.are.equal("pane-1", adopt_opts.target)
		end)

		it("warns when no current-session targets can be adopted", function()
			local warned = false

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane" },
						{ session_id = "$2", id = "%2", target = "other", kind = "pane" },
					},
				}
			end

			mocks.notify.warn = function(msg)
				warned = true
				assert.matches("No adoptable", msg)
			end

			require("wiremux.action.adopt").adopt()

			assert.is_true(warned)
		end)
	end)
end)
