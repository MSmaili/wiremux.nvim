---@module 'luassert'

describe("state", function()
	local state_module, client, query, action

	before_each(function()
		package.loaded["wiremux.backend.tmux.state"] = nil
		package.loaded["wiremux.backend.tmux.client"] = nil
		package.loaded["wiremux.backend.tmux.query"] = nil
		package.loaded["wiremux.backend.tmux.action"] = nil

		-- Mock client
		client = {
			query = function()
				return {}
			end,
			execute = function()
				return "ok"
			end,
		}

		-- Mock query
		query = {
			state = function()
				return { "show-option", "-sqv", "@wiremux_state" }
			end,
			current_pane = function()
				return { "display", "-p", "#{pane_id}" }
			end,
			list_panes = function()
				return { "list-panes", "-s", "-F", "#{pane_id} #{@wiremux_target}" }
			end,
			list_windows = function()
				return { "list-windows", "-F", "#{window_id} #{@wiremux_target}" }
			end,
		}

		-- Mock action
		action = {
			set_state = function(encoded)
				return { "set-option", "-s", "@wiremux_state", encoded }
			end,
		}

		package.loaded["wiremux.backend.tmux.client"] = client
		package.loaded["wiremux.backend.tmux.query"] = query
		package.loaded["wiremux.backend.tmux.action"] = action

		state_module = require("wiremux.backend.tmux.state")
	end)

	describe("encode", function()
		it("encodes state to JSON", function()
			local state = {
				last_used_target_id = "%1",
				instances = {
					{ id = "%1", kind = "pane" },
					{ id = "%2", kind = "pane" },
				},
			}

			local encoded = state_module.encode(state)
			local decoded = vim.json.decode(encoded)

			assert.are.equal("%1", decoded.last_used_target_id)
			assert.are.equal(2, #decoded.instances)
		end)

		it("only persists id and kind", function()
			local state = {
				instances = {
					{ id = "%1", kind = "pane", target = "test", extra = "data" },
				},
			}

			local encoded = state_module.encode(state)
			local decoded = vim.json.decode(encoded)

			assert.are.equal("%1", decoded.instances[1].id)
			assert.are.equal("pane", decoded.instances[1].kind)
			assert.is_nil(decoded.instances[1].target)
			assert.is_nil(decoded.instances[1].extra)
		end)
	end)

	describe("get", function()
		it("returns empty state when no data", function()
			client.query = function()
				return { "", "%1", "", "" }
			end

			local state = state_module.get()

			assert.are.equal(0, #state.instances)
			assert.are.equal("%1", state.origin_pane_id)
		end)

		it("decodes persisted state", function()
			local persisted = vim.json.encode({
				last_used_target_id = "%2",
				instances = {
					{ id = "%1", kind = "pane" },
					{ id = "%2", kind = "pane" },
				},
			})

			client.query = function()
				return { persisted, "%0", "%1 test1\n%2 test2", "" }
			end

			local state = state_module.get()

			assert.are.equal(2, #state.instances)
			assert.are.equal("%2", state.last_used_target_id)
		end)

		it("filters out dead instances", function()
			local persisted = vim.json.encode({
				instances = {
					{ id = "%1", kind = "pane" },
					{ id = "%2", kind = "pane" },
					{ id = "%999", kind = "pane" }, -- Dead
				},
			})

			client.query = function()
				return { persisted, "%0", "%1 test1\n%2 test2", "" }
			end

			local state = state_module.get()

			assert.are.equal(2, #state.instances)
		end)

		it("filters out origin pane", function()
			local persisted = vim.json.encode({
				instances = {
					{ id = "%0", kind = "pane" }, -- Origin
					{ id = "%1", kind = "pane" },
				},
			})

			client.query = function()
				return { persisted, "%0", "%0 origin\n%1 test", "" }
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("%1", state.instances[1].id)
		end)

		it("resolves target names from tmux", function()
			local persisted = vim.json.encode({
				instances = {
					{ id = "%1", kind = "pane" },
				},
			})

			client.query = function()
				return { persisted, "%0", "%1 my-target", "" }
			end

			local state = state_module.get()

			assert.are.equal("my-target", state.instances[1].target)
		end)

		it("clears last_used_target_id if dead", function()
			local persisted = vim.json.encode({
				last_used_target_id = "%999",
				instances = {
					{ id = "%1", kind = "pane" },
				},
			})

			client.query = function()
				return { persisted, "%0", "%1 test", "" }
			end

			local state = state_module.get()

			assert.is_nil(state.last_used_target_id)
		end)
	end)

	describe("set", function()
		it("encodes and saves state", function()
			local executed_cmd
			client.execute = function(cmds)
				executed_cmd = cmds[1]
				return "ok"
			end

			local state = {
				last_used_target_id = "%1",
				instances = {
					{ id = "%1", kind = "pane" },
				},
			}

			state_module.set(state)

			assert.are.equal("set-option", executed_cmd[1])
			assert.are.equal("@wiremux_state", executed_cmd[3])
			assert.is_not_nil(executed_cmd[4]) -- Encoded state
		end)
	end)
end)
