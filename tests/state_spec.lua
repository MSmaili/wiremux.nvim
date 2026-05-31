---@module 'luassert'

local helpers = require("tests.helpers")

describe("state", function()
	local state_module, client, query

	before_each(function()
		helpers.clear({
			"wiremux.backend.tmux.state",
			"wiremux.backend.tmux.client",
			"wiremux.backend.tmux.query",
		})

		client = {
			query = function()
				return {}
			end,
		}

		query = {
			current_pane = function()
				return { "display", "-p", "#{pane_id}:#{session_id}" }
			end,
			list_panes = function()
				return {
					"list-panes",
					"-a",
					"-F",
					"#{session_id}:#{pane_id}:#{window_id}:#{@wiremux_target}:#{@wiremux_origin}:#{@wiremux_origin_cwd}:#{@wiremux_kind}:#{@wiremux_last_used_at}:#{window_name}:#{window_index}:#{pane_index}:#{pane_current_command}",
				}
			end,
		}

		helpers.register({
			["wiremux.backend.tmux.client"] = client,
			["wiremux.backend.tmux.query"] = query,
		})

		state_module = require("wiremux.backend.tmux.state")
	end)

	describe("get", function()
		it("returns empty state when no panes have metadata", function()
			client.query = function()
				return { "%1:$1", "" }
			end

			local state = state_module.get()

			assert.are.equal(0, #state.instances)
			assert.are.equal("%1", state.origin_pane_id)
			assert.are.equal("$1", state.session_id)
		end)

		it("parses pane metadata", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:test1:%0:/home:pane:1000::1:0:zsh\n$1:%2:@1:test2:%0:/home:pane:2000::1:1:npm\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(2, #state.instances)
			assert.are.equal("$1", state.instances[1].session_id)
			assert.are.equal("%1", state.instances[1].id)
			assert.are.equal("test1", state.instances[1].target)
			assert.are.equal("%0", state.instances[1].origin)
			assert.are.equal("/home", state.instances[1].origin_cwd)
			assert.are.equal("pane", state.instances[1].kind)
			assert.are.equal(1000, state.instances[1].last_used_at)
		end)

		it("extracts last_used_target_id from pane metadata", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:test1:%0:/home:pane:1000::1:0:zsh\n$1:%2:@1:test2:%0:/home:pane:2000::1:1:zsh\n",
				}
			end

			local state = state_module.get()

			assert.are.equal("%2", state.last_used_target_id)
		end)

		it("skips panes without target metadata", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1::%0:/home:pane:1000::1:0:zsh\n$1:%2:@1:test:%0:/home:pane:2000::1:1:zsh\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal(2, #state.panes)
			assert.are.equal("%2", state.instances[1].id)
		end)

		it("keeps unmanaged panes out of managed instances", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:::/home:pane:::1:0:zsh\n$1:%2:@1:test:%0:/home:pane:2000::1:1:npm\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(2, #state.panes)
			assert.is_nil(state.panes[1].target)
			assert.are.equal(1, #state.instances)
			assert.are.equal("%2", state.instances[1].id)
		end)

		it("handles window kind", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:test:%0:/home:window:1000:mywindow:1:0:zsh\n",
				}
			end

			local state = state_module.get()

			assert.are.equal("window", state.instances[1].kind)
			assert.are.equal("mywindow", state.instances[1].window_name)
		end)

		it("handles empty metadata fields", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:test:::pane:1000::1:0:\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.is_nil(state.instances[1].origin)
			assert.is_nil(state.instances[1].origin_cwd)
		end)

		it("parses running_command field", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:test:%0:/home:pane:1000::1:0:npm\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("npm", state.instances[1].running_command)
		end)

		it("handles colons in running_command", function()
			client.query = function()
				return {
					"%0:$1",
					"$1:%1:@1:test:%0:/home:pane:1000::1:0:node:inspect\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("node:inspect", state.instances[1].running_command)
		end)

		it("handles malformed lines gracefully", function()
			client.query = function()
				return {
					"%0:$1",
					"invalid\n$1:%1:@1:test:%0:/home:pane:1000::1:0:zsh\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("%1", state.instances[1].id)
		end)
	end)

	describe("adopt", function()
		it("rewrites origin metadata and updates state", function()
			local captured_cmds
			client.execute = function(cmds)
				captured_cmds = cmds
				return true
			end

			local target = {
				session_id = "$1",
				id = "%2",
				window_id = "@1",
				target = "test",
				origin = "%old",
				kind = "pane",
			}
			local state = { origin_pane_id = "%0", session_id = "$1", instances = { target } }

			local ok = state_module.adopt(target, state)

			assert.is_true(ok)
			assert.are.equal("%0", target.origin)
			assert.are.equal(vim.fn.getcwd(), target.origin_cwd)
			assert.are.equal("%2", state.last_used_target_id)
			assert.are.equal("@wiremux_origin", captured_cmds[1][5])
			assert.are.equal("%0", captured_cmds[1][6])
			assert.are.equal("@wiremux_origin_cwd", captured_cmds[2][5])
			assert.are.equal("@wiremux_last_used_at", captured_cmds[3][5])
		end)

		it("assigns target metadata when adopting unmanaged panes", function()
			local captured_cmds
			client.execute = function(cmds)
				captured_cmds = cmds
				return true
			end

			local target = {
				session_id = "$1",
				id = "%2",
				window_id = "@1",
				kind = "pane",
			}
			local state = { origin_pane_id = "%0", session_id = "$1", instances = {}, panes = { target } }

			local ok = state_module.adopt(target, state, "terminal")

			assert.is_true(ok)
			assert.are.equal("terminal", target.target)
			assert.are.equal(1, #state.instances)
			assert.are.equal("@wiremux_target", captured_cmds[1][5])
			assert.are.equal("terminal", captured_cmds[1][6])
			assert.are.equal("@wiremux_kind", captured_cmds[2][5])
			assert.are.equal("@wiremux_origin", captured_cmds[3][5])
		end)
	end)
end)
