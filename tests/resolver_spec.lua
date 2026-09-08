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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test1" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test2" },
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{
						id = "%1",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "test",
						window_index = 1,
						pane_index = 1,
					},
					{
						id = "%2",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "test",
						window_index = 1,
						pane_index = 2,
					},
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
			assert.are.equal("instance", result.items[1].type)
			assert.are.equal("[m] 1:1    test", result.items[1].label)
			assert.are.equal("[m] 1:2    test", result.items[2].label)
		end)

		it("skips picker when only one instance exists", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
		end)

		it("keeps items on same order", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "zebra" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "alpha" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("[m] 1      zebra", result.items[1].label)
			assert.are.equal("[m] 2      alpha", result.items[2].label)
		end)
	end)

	describe("resolve with behavior='last'", function()
		it("returns last used target", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test1" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test2" },
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test1" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test2" },
				},
				last_used_target_id = "%999",
			}

			local result = resolver.resolve(state, {}, { behavior = "last" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
		end)

		it("returns single instance if only one exists", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test" },
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test" },
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

	describe("resolve with mode='auto'", function()
		it("shows only managed instances while any are available", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ session_id = "$1", id = "%1", managed = true, kind = "pane", target = "one", origin = "%0" },
					{ session_id = "$1", id = "%2", managed = true, kind = "pane", target = "two", origin = "%0" },
					{ session_id = "$1", id = "%4", managed = true, kind = "pane", target = "other", origin = "%99" },
				},
				panes = {
					{ session_id = "$1", id = "%3", managed = false, kind = "pane", running_command = "zsh" },
				},
			}

			local result = resolver.resolve(state, { server = { kind = "pane" } }, {
				behavior = "pick",
				mode = "auto",
				allow_adopt = true,
			})

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
			assert.are.equal("instance", result.items[1].type)
			assert.are.equal("instance", result.items[2].type)
		end)

		it("prompts from a new origin instead of reusing another origin's managed target", function()
			local managed = {
				id = "%1",
				window_id = "@1",
				kind = "pane",
				managed = true,
				target = "pi",
				origin = "%99",
				session_id = "$1",
			}
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				last_used_target_id = managed.id,
				instances = { managed },
				panes = {
					managed,
					{ id = "%0", window_id = "@2", kind = "pane", managed = false, session_id = "$1" },
					{ id = "%2", window_id = "@2", kind = "pane", managed = false, session_id = "$1" },
				},
			}
			for _, behavior in ipairs({ "pick", "last" }) do
				local result = resolver.resolve(state, { server = { kind = "pane" } }, {
					behavior = behavior,
					mode = "auto",
					allow_adopt = true,
				})
				assert.are.equal("pick", result.kind)
				assert.are.equal(2, #result.items)
				assert.are.equal("adopt", result.items[1].type)
				assert.are.equal("%2", result.items[1].instance.id)
				assert.are.equal("definition", result.items[2].type)
			end
			state.origin_pane_id = managed.origin
			local result = resolver.resolve(state, {}, { behavior = "pick", mode = "auto", allow_adopt = true })
			assert.are.equal("targets", result.kind)
			assert.are.same({ managed }, result.targets)
		end)

		it("offers unmanaged instances and definitions when no managed instance is available", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {},
				panes = {
					{ session_id = "$1", id = "%1", managed = false, kind = "pane", running_command = "opencode" },
					{ session_id = "$2", id = "%2", managed = false, kind = "pane", running_command = "zsh" },
				},
			}

			local result = resolver.resolve(state, { server = { kind = "pane" } }, {
				behavior = "pick",
				mode = "auto",
				allow_adopt = true,
			})

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
			assert.are.equal("adopt", result.items[1].type)
			assert.are.equal("definition", result.items[2].type)
		end)
	end)

	describe("resolve with mode='all'", function()
		it("shows managed instances, current-session unmanaged instances, and definitions", function()
			local managed =
				{ session_id = "$1", id = "%1", managed = true, kind = "pane", target = "test", origin = "%0" }
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = { managed },
				panes = {
					managed,
					{ session_id = "$1", id = "%0", managed = false, kind = "pane", running_command = "nvim" },
					{
						session_id = "$1",
						id = "%2",
						managed = false,
						kind = "pane",
						window_index = 1,
						pane_index = 2,
						running_command = "opencode",
					},
					{ session_id = "$2", id = "%3", managed = false, kind = "pane", running_command = "zsh" },
				},
			}

			local result = resolver.resolve(state, { server = { kind = "pane" } }, {
				behavior = "pick",
				mode = "all",
				allow_adopt = true,
			})

			assert.are.equal("pick", result.kind)
			assert.are.equal(3, #result.items)
			assert.are.equal("instance", result.items[1].type)
			assert.is_true(result.items[1].instance.managed)
			assert.are.equal("adopt", result.items[2].type)
			assert.is_false(result.items[2].instance.managed)
			assert.matches("%[~%]%s+1:2%s+opencode", result.items[2].label)
			assert.are.equal("definition", result.items[3].type)
			assert.are.equal("[+] server", result.items[3].label)
		end)

		it("uses the same instance filter without mutating managed and unmanaged candidates", function()
			local seen = {}
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ session_id = "$1", id = "%1", managed = true, kind = "pane", target = "test", origin = "%0" },
				},
				panes = {
					{ session_id = "$1", id = "%2", managed = false, kind = "pane", running_command = "opencode" },
					{ session_id = "$1", id = "%3", managed = false, kind = "pane", running_command = "zsh" },
				},
			}
			local before = vim.deepcopy(state)

			local result = resolver.resolve(state, {}, {
				behavior = "pick",
				mode = "all",
				allow_adopt = true,
				filter = {
					instances = function(inst)
						table.insert(seen, inst.managed)
						return inst.managed or inst.running_command == "opencode"
					end,
				},
			})

			assert.are.same(before, state)
			assert.are.same({ true, false, false }, seen)
			assert.are.equal(2, #result.items)
			assert.are.equal("instance", result.items[1].type)
			assert.are.equal("adopt", result.items[2].type)
		end)

		it("does not inspect unmanaged candidates for direct last or bulk delivery", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				last_used_target_id = "%1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test1" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test2" },
				},
				panes = { { session_id = "$1", id = "%3", managed = false, kind = "pane" } },
			}
			for _, behavior in ipairs({ "last", "all" }) do
				local result = resolver.resolve(state, { server = { kind = "pane" } }, {
					behavior = behavior,
					mode = "all",
					allow_adopt = true,
					filter = {
						instances = function(inst)
							return inst.target:match("^test") ~= nil
						end,
					},
				})
				assert.are.equal("targets", result.kind)
				assert.are.equal(behavior == "all" and 2 or 1, #result.targets)
				assert.are.equal("%1", result.targets[1].id)
			end
		end)

		it("keeps adoption explicit when last or bulk delivery has no managed targets", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {},
				panes = { { session_id = "$1", id = "%1", managed = false, kind = "pane" } },
			}
			for _, behavior in ipairs({ "last", "all" }) do
				local result = resolver.resolve(state, {}, { behavior = behavior, mode = "all", allow_adopt = true })
				assert.are.equal("pick", result.kind)
				assert.are.equal(1, #result.items)
				assert.are.equal("adopt", result.items[1].type)
			end
		end)
	end)

	it("keeps cross-session panes distinct and sorts only the managed group", function()
		require("wiremux.config").opts.picker.instances.sort = function(a, b)
			return a.target > b.target
		end
		local state = { origin_pane_id = "%0", session_id = "$1", instances = {}, panes = {} }
		for i = 1, 3 do
			local managed = {
				id = "%" .. i,
				managed = true,
				origin = "%0",
				target = "pane-" .. i,
				kind = "pane",
				session_id = "$" .. i,
				window_index = 1,
				pane_index = 0,
				running_command = "zsh",
			}
			table.insert(state.instances, managed)
			table.insert(state.panes, managed)
			table.insert(state.panes, {
				id = "%" .. (i + 3),
				managed = false,
				kind = "pane",
				session_id = "$" .. i,
				window_index = 1,
				pane_index = 1,
				running_command = "zsh",
			})
		end
		local result = resolver.resolve(state, {}, {
			behavior = "pick",
			mode = "all",
			allow_adopt = true,
			filter = {
				instances = function()
					return true
				end,
			},
		})
		assert.are.equal(6, #result.items)
		assert.are.same(
			{
				"[m] $3:1:0 zsh",
				"[m] $2:1:0 zsh",
				"[m] 1:0    zsh",
				"[~] 1:1    zsh",
				"[~] $2:1:1 zsh",
				"[~] $3:1:1 zsh",
			},
			vim.tbl_map(function(item)
				return item.label
			end, result.items)
		)
	end)

	describe("label with running_command", function()
		it("replaces generated target names with useful pane context", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{
						id = "%14",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "pane-14",
						window_index = 1,
						pane_index = 2,
						running_command = "node",
					},
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("[m] 1:2    node", result.items[1].label)
		end)

		it("includes running_command in label", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{
						id = "%1",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "test",
						running_command = "npm",
					},
					{
						id = "%2",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "test",
						running_command = "node",
					},
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal("[m] 1      test [npm]", result.items[1].label)
			assert.are.equal("[m] 2      test [node]", result.items[2].label)
		end)

		it("omits running_command bracket when empty", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "test" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("[m] 1      test", result.items[1].label)
			assert.are.equal("[m] 2      test", result.items[2].label)
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{
						id = "%1",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "myapp",
						running_command = "npm",
					},
					{
						id = "%2",
						managed = true,
						session_id = "$1",
						origin = "%0",
						kind = "pane",
						target = "myapp",
						running_command = "node",
					},
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "myapp" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "myapp" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal("[m] 1      myapp", result.items[1].label)
			assert.are.equal("[m] 2      myapp", result.items[2].label)
		end)
	end)

	describe("resolve with explicit target", function()
		it("sends directly to matching instance", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "shell" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "ai" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "pick", target = "shell" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
		end)

		it("returns definition to auto-create when no matching instance exists", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "ai" },
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "shell" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "shell" },
					{ id = "%3", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "ai" },
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
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "shell" },
					{ id = "%2", managed = true, session_id = "$1", origin = "%0", kind = "pane", target = "shell" },
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

			local state = { origin_pane_id = "%0", session_id = "$1", instances = {} }

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
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", kind = "pane", target = "shell", origin = "%0" },
					{ id = "%2", managed = true, session_id = "$1", kind = "pane", target = "shell", origin = "%99" },
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
			local state = { origin_pane_id = "%0", session_id = "$1", instances = {} }
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
			local state = { origin_pane_id = "%0", session_id = "$1", instances = {} }

			local result = resolver.resolve(state, {}, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(0, #result.items)
		end)
	end)
end)
