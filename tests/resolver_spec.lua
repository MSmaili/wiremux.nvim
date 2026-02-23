---@module 'luassert'

describe("resolver", function()
	local resolver

	before_each(function()
		package.loaded["wiremux.core.resolver"] = nil
		package.loaded["wiremux.config"] = nil
		resolver = require("wiremux.core.resolver")
	end)

	describe("resolve with behavior='all'", function()
		it("returns all instances", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test1" },
					{ id = "%2", kind = "pane", target = "test2" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "all" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(2, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
			assert.are.equal("%2", result.targets[2].id)
		end)
	end)

	describe("resolve with behavior='pick'", function()
		it("returns picker items for instances", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test" },
					{ id = "%2", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
			assert.are.equal("instance", result.items[1].type)
			assert.are.equal("test 1", result.items[1].label)
			assert.are.equal("test 2", result.items[2].label)
		end)

		it("skips picker when only one instance exists", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
		end)

		it("keeps items on same order", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "zebra" },
					{ id = "%2", kind = "pane", target = "alpha" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("zebra 1", result.items[1].label)
			assert.are.equal("alpha 2", result.items[2].label)
		end)
	end)

	describe("resolve with behavior='last'", function()
		it("returns last used target", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test1" },
					{ id = "%2", kind = "pane", target = "test2" },
				},
				last_used_target_id = "%2",
			}

			local result = resolver.resolve(state, {}, { behavior = "last" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%2", result.targets[1].id)
		end)

		it("falls back to picker if last_used not found", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test1" },
					{ id = "%2", kind = "pane", target = "test2" },
				},
				last_used_target_id = "%999",
			}

			local result = resolver.resolve(state, {}, { behavior = "last" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
		end)

		it("returns single instance if only one exists", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "last" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
		end)
	end)

	describe("resolve with mode='definitions'", function()
		it("returns only definitions", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test" },
				},
			}
			local definitions = {
				server = { kind = "pane" },
				logs = { kind = "window" },
			}

			local result = resolver.resolve(state, definitions, { behavior = "pick", mode = "definitions" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
			assert.are.equal("definition", result.items[1].type)
		end)
	end)

	describe("label with running_command", function()
		it("includes running_command in label", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test", running_command = "npm" },
					{ id = "%2", kind = "pane", target = "test", running_command = "node" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal("test 1 [npm]", result.items[1].label)
			assert.are.equal("test 2 [node]", result.items[2].label)
		end)

		it("omits running_command bracket when empty", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test" },
					{ id = "%2", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("test 1", result.items[1].label)
			assert.are.equal("test 2", result.items[2].label)
		end)
	end)

	describe("function label", function()
		it("calls function label with inst and index", function()
			local captured_inst, captured_index
			local label_fn = function(inst, index)
				captured_inst = inst
				captured_index = index
				return "custom " .. index .. " (" .. (inst.running_command or "") .. ")"
			end

			local config = require("wiremux.config")
			config.opts.targets = {
				definitions = {
					myapp = { label = label_fn },
				},
			}

			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "myapp", running_command = "npm" },
					{ id = "%2", kind = "pane", target = "myapp", running_command = "node" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal("custom 1 (npm)", result.items[1].label)
			assert.are.equal("custom 2 (node)", result.items[2].label)
			assert.are.equal("%2", captured_inst.id)
			assert.are.equal(2, captured_index)
		end)

		it("handles function label error gracefully", function()
			local config = require("wiremux.config")
			config.opts.targets = {
				definitions = {
					myapp = {
						label = function()
							error("label failed")
						end,
					},
				},
			}

			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "myapp" },
					{ id = "%2", kind = "pane", target = "myapp" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal("myapp 1", result.items[1].label)
			assert.are.equal("myapp 2", result.items[2].label)
		end)
	end)

	describe("resolve with explicit target", function()
		it("sends directly to matching instance", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "shell" },
					{ id = "%2", kind = "pane", target = "ai" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick", target = "shell" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
		end)

		it("returns definition to auto-create when no matching instance exists", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "ai" },
				},
			}
			local definitions = {
				shell = { kind = "pane", cmd = "bash" },
			}

			local result = resolver.resolve(state, definitions, { behavior = "pick", target = "shell" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(1, #result.items)
			assert.are.equal("definition", result.items[1].type)
			assert.are.equal("shell", result.items[1].target)
			assert.are.equal("bash", result.items[1].def.cmd)
		end)

		it("shows picker when two matching instances exist", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "shell" },
					{ id = "%2", kind = "pane", target = "shell" },
					{ id = "%3", kind = "pane", target = "ai" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick", target = "shell" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
			assert.are.equal("shell", result.items[1].target)
			assert.are.equal("shell", result.items[2].target)
		end)

		it("respects behavior='last' among matching instances", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "shell" },
					{ id = "%2", kind = "pane", target = "shell" },
				},
				last_used_target_id = "%2",
			}

			local result = resolver.resolve(state, {}, { behavior = "last", target = "shell" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%2", result.targets[1].id)
		end)

		it("warns when target definition does not exist", function()
			local warned = false
			package.loaded["wiremux.utils.notify"] = {
				warn = function(msg)
					warned = true
					assert.matches("not found", msg)
				end,
				debug = function() end,
			}

			local state = { instances = {} }

			local result = resolver.resolve(state, {}, { behavior = "pick", target = "nonexistent" })

			assert.is_true(warned)
			assert.are.equal("pick", result.kind)
			assert.are.equal(0, #result.items)
		end)

		it("applies instance filters before target filtering", function()
			local config = require("wiremux.config")
			config.opts.picker = {
				instances = {
					filter = function(inst)
						return inst.origin == "%0"
					end,
				},
			}

			local state = {
				origin_pane_id = "%0",
				instances = {
					{ id = "%1", kind = "pane", target = "shell", origin = "%0" },
					{ id = "%2", kind = "pane", target = "shell", origin = "%99" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick", target = "shell" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
		end)
	end)

	describe("resolve with no instances", function()
		it("falls back to definitions", function()
			local state = { instances = {} }
			local definitions = {
				server = { kind = "pane" },
			}

			local result = resolver.resolve(state, definitions, { behavior = "last" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(1, #result.items)
			assert.are.equal("definition", result.items[1].type)
			assert.are.equal("server", result.items[1].target)
		end)

		it("returns empty items if no definitions", function()
			local state = { instances = {} }

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(0, #result.items)
		end)
	end)
end)
