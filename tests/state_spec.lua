---@module 'luassert'

describe("state", function()
	local state_module, client, query

	before_each(function()
		package.loaded["wiremux.backend.tmux.state"] = nil
		package.loaded["wiremux.backend.tmux.client"] = nil
		package.loaded["wiremux.backend.tmux.query"] = nil

		-- Mock client
		client = {
			query = function()
				return {}
			end,
		}

		-- Mock query
		query = {
			current_pane = function()
				return { "display", "-p", "#{pane_id}" }
			end,
			list_panes = function()
				return {
					"list-panes",
					"-a",
					"-F",
					"#{pane_id}:#{window_id}:#{@wiremux_target}:#{@wiremux_origin}:#{@wiremux_origin_cwd}:#{@wiremux_kind}:#{@wiremux_last_used}",
				}
			end,
		}

		package.loaded["wiremux.backend.tmux.client"] = client
		package.loaded["wiremux.backend.tmux.query"] = query

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
					"%1:@1:test1:%0:/home:pane:false\n%2:@1:test2:%0:/home:pane:true",
				}
			end

			local state = state_module.get()

			assert.are.equal(2, #state.instances)
			assert.are.equal("%1", state.instances[1].id)
			assert.are.equal("test1", state.instances[1].target)
			assert.are.equal("%0", state.instances[1].origin)
			assert.are.equal("/home", state.instances[1].origin_cwd)
			assert.are.equal("pane", state.instances[1].kind)
			assert.are.equal(false, state.instances[1].last_used)
		end)

		it("extracts last_used_target_id from pane metadata", function()
			client.query = function()
				return {
					"%0",
					"%1:@1:test1:%0:/home:pane:false\n%2:@1:test2:%0:/home:pane:true",
				}
			end

			local state = state_module.get()

			assert.are.equal("%2", state.last_used_target_id)
		end)

		it("skips panes without target metadata", function()
			client.query = function()
				return {
					"%0",
					"%1:@1::%0:/home:pane:false\n%2:@1:test:%0:/home:pane:false",
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
					"%1:@1:test:%0:/home:window:false",
				}
			end

			local state = state_module.get()

			assert.are.equal("window", state.instances[1].kind)
		end)

		it("handles empty metadata fields", function()
			client.query = function()
				return {
					"%0",
					"%1:@1:test:::pane:false",
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
					"invalid\n%1:@1:test:%0:/home:pane:false",
				}
			end

			local state = state_module.get()

			assert.are.equal(1, #state.instances)
			assert.are.equal("%1", state.instances[1].id)
		end)
	end)
end)
