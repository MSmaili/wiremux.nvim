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
				return { "display", "-p", "#{pane_id}" }
			end,
			list_panes = function()
				return {
					"list-panes",
					"-a",
					"-F",
					"#{pane_id}:#{window_id}:#{@wiremux_target}:#{@wiremux_origin}:#{@wiremux_origin_cwd}:#{@wiremux_kind}:#{@wiremux_last_used_at}:#{window_name}",
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
				return { "%1", "" }
			end

			local state = state_module.get()

			assert.are.equal(0, #state.instances)
			assert.are.equal("%1", state.origin_pane_id)
		end)

		it("parses pane metadata", function()
			client.query = function()
				return {
					"%0",
					"%1:@1:test1:%0:/home:pane:1000:\n%2:@1:test2:%0:/home:pane:2000:\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(2, #state.instances)
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
					"%0",
					"%1:@1:test1:%0:/home:pane:1000:\n%2:@1:test2:%0:/home:pane:2000:\n",
				}
			end

			local state = state_module.get()

			assert.are.equal("%2", state.last_used_target_id)
		end)

		it("skips panes without target metadata", function()
			client.query = function()
				return {
					"%0",
					"%1:@1::%0:/home:pane:1000:\n%2:@1:test:%0:/home:pane:2000:\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("%2", state.instances[1].id)
		end)

		it("handles window kind", function()
			client.query = function()
				return {
					"%0",
					"%1:@1:test:%0:/home:window:1000:mywindow\n",
				}
			end

			local state = state_module.get()

			assert.are.equal("window", state.instances[1].kind)
			assert.are.equal("mywindow", state.instances[1].window_name)
		end)

		it("handles empty metadata fields", function()
			client.query = function()
				return {
					"%0",
					"%1:@1:test:::pane:1000:\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.is_nil(state.instances[1].origin)
			assert.is_nil(state.instances[1].origin_cwd)
		end)

		it("handles malformed lines gracefully", function()
			client.query = function()
				return {
					"%0",
					"invalid\n%1:@1:test:%0:/home:pane:1000:\n",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("%1", state.instances[1].id)
		end)
	end)
end)
