---@module 'luassert'

local helpers = require("tests.helpers")

describe("state", function()
	local state_module, client, query

	local function render(format, values)
		return (format:gsub("#{(.-)}", function(name)
			return values[name] or ""
		end))
	end

	local function current_pane(values)
		return render(query.current_pane()[3], values or { pane_id = "%0", session_id = "$1" })
	end

	local function pane(values)
		return render(
			query.list_panes()[4],
			vim.tbl_extend("force", {
				session_id = "$1",
				pane_id = "%1",
				window_id = "@1",
				window_index = "1",
				pane_index = "0",
			}, values)
		)
	end

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
			query_async = function(cmds, callback)
				callback(client.query(cmds))
			end,
		}

		query = require("wiremux.backend.tmux.query")

		helpers.register({
			["wiremux.backend.tmux.client"] = client,
		})

		state_module = require("wiremux.backend.tmux.state")
	end)

	for _, method in ipairs({ "get", "get_async" }) do
		describe(method, function()
			local function get()
				if method == "get" then
					return state_module.get()
				end
				local result, calls = nil, 0
				state_module.get_async(function(state)
					result, calls = state, calls + 1
				end)
				assert.are.equal(1, calls)
				return result
			end

			it("returns empty state when no panes have metadata", function()
				client.query = function()
					return { current_pane({ pane_id = "%1", session_id = "$1" }), "" }
				end

				local state = get()

				assert.are.equal(0, #state.instances)
				assert.are.equal("%1", state.origin_pane_id)
				assert.are.equal("$1", state.session_id)
			end)

			it("parses pane metadata", function()
				client.query = function()
					return {
						current_pane(),
						pane({
							["@wiremux_target"] = "test1",
							["@wiremux_origin"] = "%0",
							["@wiremux_origin_cwd"] = "/home",
							["@wiremux_kind"] = "pane",
							["@wiremux_last_used_at"] = "1000",
							pane_current_command = "zsh",
						}) .. "\n" .. pane({
							pane_id = "%2",
							["@wiremux_target"] = "test2",
							["@wiremux_last_used_at"] = "2000",
						}),
					}
				end

				local state = get()

				assert.are.equal(2, #state.instances)
				assert.are.equal("$1", state.instances[1].session_id)
				assert.are.equal("%1", state.instances[1].id)
				assert.are.equal("test1", state.instances[1].target)
				assert.is_true(state.instances[1].managed)
				assert.are.equal("%0", state.instances[1].origin)
				assert.are.equal("/home", state.instances[1].origin_cwd)
				assert.are.equal("pane", state.instances[1].kind)
				assert.are.equal(1000, state.instances[1].last_used_at)
			end)

			it("extracts last_used_target_id from pane metadata", function()
				client.query = function()
					return {
						current_pane(),
						pane({ ["@wiremux_target"] = "test1", ["@wiremux_last_used_at"] = "1000" }) .. "\n" .. pane({
							pane_id = "%2",
							["@wiremux_target"] = "test2",
							["@wiremux_last_used_at"] = "2000",
						}),
					}
				end

				local state = get()

				assert.are.equal("%2", state.last_used_target_id)
			end)

			it("skips panes without target metadata", function()
				client.query = function()
					return {
						current_pane(),
						pane({ ["@wiremux_last_used_at"] = "1000" })
							.. "\n"
							.. pane({ pane_id = "%2", ["@wiremux_target"] = "test", ["@wiremux_last_used_at"] = "2000" }),
					}
				end

				local state = get()

				assert.are.equal(1, #state.instances)
				assert.are.equal(2, #state.panes)
				assert.are.equal("%2", state.instances[1].id)
			end)

			it("keeps unmanaged panes out of managed instances", function()
				client.query = function()
					return {
						current_pane(),
						pane({}) .. "\n" .. pane({ pane_id = "%2", ["@wiremux_target"] = "test" }),
					}
				end

				local state = get()

				assert.are.equal(2, #state.panes)
				assert.is_false(state.panes[1].managed)
				assert.is_nil(state.panes[1].target)
				assert.is_true(state.panes[2].managed)
				assert.are.equal(1, #state.instances)
				assert.are.equal("%2", state.instances[1].id)
			end)

			it("handles window kind", function()
				client.query = function()
					return {
						current_pane(),
						pane({ ["@wiremux_target"] = "test", ["@wiremux_kind"] = "window", window_name = "mywindow" }),
					}
				end

				local state = get()

				assert.are.equal("window", state.instances[1].kind)
				assert.are.equal("mywindow", state.instances[1].window_name)
			end)

			it("handles empty metadata fields", function()
				client.query = function()
					return {
						current_pane(),
						pane({ ["@wiremux_target"] = "test" }) .. "\n",
					}
				end

				local state = get()

				assert.are.same({
					session_id = "$1",
					id = "%1",
					window_id = "@1",
					managed = true,
					target = "test",
					kind = "pane",
					window_index = 1,
					pane_index = 0,
				}, state.instances[1])
			end)

			it("parses running_command field", function()
				client.query = function()
					return {
						current_pane(),
						pane({ ["@wiremux_target"] = "test", pane_current_command = "npm" }),
					}
				end

				local state = get()

				assert.are.equal(1, #state.instances)
				assert.are.equal("npm", state.instances[1].running_command)
			end)

			it("preserves colons in every text field without shifting positions", function()
				client.query = function(cmds)
					assert.are.same({ query.current_pane(), query.list_panes() }, cmds)
					return {
						current_pane(),
						pane({
							["@wiremux_target"] = "api:dev",
							["@wiremux_origin"] = "%0",
							["@wiremux_origin_cwd"] = "/home/work:api",
							["@wiremux_kind"] = "window",
							["@wiremux_last_used_at"] = "1000",
							window_name = "work:api",
							window_index = "12",
							pane_index = "3",
							pane_current_command = "node:inspect",
						}),
					}
				end

				local state = get()

				assert.are.same({
					session_id = "$1",
					id = "%1",
					window_id = "@1",
					managed = true,
					target = "api:dev",
					origin = "%0",
					origin_cwd = "/home/work:api",
					kind = "window",
					last_used_at = 1000,
					window_name = "work:api",
					window_index = 12,
					pane_index = 3,
					running_command = "node:inspect",
				}, state.instances[1])
			end)

			it("rejects malformed field counts and separator collisions", function()
				local separator = query.FIELD_SEPARATOR
				assert.are.equal("\31", separator)
				assert.is_nil(separator:match("%s"))
				local valid = pane({ ["@wiremux_target"] = "test", ["@wiremux_last_used_at"] = "1000" })
				local lines = { "invalid", valid:sub(1, -2), valid .. separator .. "extra" }
				for _, field in ipairs({
					"@wiremux_target",
					"@wiremux_origin_cwd",
					"window_name",
					"pane_current_command",
				}) do
					for _, value in ipairs({ separator, "left" .. separator .. "right" }) do
						table.insert(lines, pane({ [field] = value, ["@wiremux_last_used_at"] = "2000" }))
					end
				end
				table.insert(lines, valid)
				client.query = function()
					return { current_pane(), vim.trim(table.concat(lines, "\n") .. "\n") }
				end

				local state = get()

				assert.are.equal(1, #state.panes)
				assert.are.equal(1, #state.instances)
				assert.are.equal("%1", state.instances[1].id)
				assert.are.equal(1000, state.instances[1].last_used_at)
			end)

			it("rejects invalid IDs and nonempty invalid positions", function()
				for field, values in pairs({
					session_id = { "", "1", "$x", "$1:2" },
					pane_id = { "", "1", "%x", "%1:2" },
					window_id = { "", "1", "@x", "@1:2" },
					["@wiremux_origin"] = { "1", "%x", "%1:2" },
					window_index = { "x", "1:2", "-1", "1.5", "1e2" },
					pane_index = { "x", "1:2", "-1", "1.5", "1e2" },
				}) do
					for _, value in ipairs(values) do
						client.query = function()
							return { current_pane(), pane({ [field] = value, ["@wiremux_target"] = "test" }) }
						end
						local state = get()
						assert.are.same({}, state.panes, field .. "=" .. value)
						assert.are.same({}, state.instances)
						assert.is_nil(state.last_used_target_id)
					end
				end
			end)

			it("rejects malformed current-pane records without shifting IDs", function()
				for _, current in ipairs({
					"",
					"%0",
					current_pane() .. query.FIELD_SEPARATOR .. "extra",
					current_pane({ pane_id = "", session_id = "$1" }),
					current_pane({ pane_id = "%0", session_id = "" }),
					current_pane({ pane_id = "%x", session_id = "$1" }),
					current_pane({ pane_id = "%0", session_id = "$x" }),
					current_pane({ pane_id = "%0" .. query.FIELD_SEPARATOR .. "%2", session_id = "$1" }),
				}) do
					client.query = function()
						return { current, pane({}) }
					end
					local state = get()
					assert.is_nil(state.origin_pane_id)
					assert.is_nil(state.session_id)
					assert.are.equal(1, #state.panes)
				end
			end)

			it("keeps empty optional fields without shifting or dropping the pane", function()
				client.query = function()
					return { current_pane(), vim.trim(pane({ window_index = "", pane_index = "" }) .. "\n") }
				end

				local state = get()

				assert.are.same({
					{ session_id = "$1", id = "%1", window_id = "@1", managed = false, kind = "pane" },
				}, state.panes)
				assert.are.same({}, state.instances)
			end)
		end)
	end

	it("passes asynchronous query errors to the callback", function()
		client.query_async = function(_, callback)
			callback(nil)
		end
		local calls = 0
		state_module.get_async(function(state)
			calls = calls + 1
			assert.is_nil(state)
		end)
		assert.are.equal(1, calls)
	end)

	describe("adopt", function()
		it("defaults missing and empty names to the numeric pane ID", function()
			for _, case in ipairs({
				{ id = "%0", expected = "pane-0" },
				{ id = "%42", target = "", name = "", expected = "pane-42" },
			}) do
				local target = { id = case.id, window_id = "@1", kind = "pane", managed = false, target = case.target }
				local state = { origin_pane_id = "%1", instances = {}, panes = { target } }
				local before_target, before_state = vim.deepcopy(target), vim.deepcopy(state)
				local captured_cmds
				client.execute = function(cmds)
					assert.are.same(before_target, target)
					assert.are.same(before_state, state)
					captured_cmds = cmds
					return ""
				end

				assert.is_true(state_module.adopt(target, state, case.name))
				assert.are.equal(case.expected, target.target)
				assert.is_true(target.managed)
				assert.are.equal(case.id, state.last_used_target_id)
				assert.are.equal(target, state.instances[1])
				assert.are.equal(target, state.panes[1])
				assert.are.equal("@wiremux_target", captured_cmds[1][5])
				assert.are.equal(target.target, captured_cmds[1][6])
			end
		end)

		it("preserves a known target while rewriting origin metadata and updating state", function()
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

			local ok = state_module.adopt(target, state, "replacement")

			assert.is_true(ok)
			assert.are.equal("test", target.target)
			assert.are.equal(1, #state.instances)
			assert.are.equal(3, #captured_cmds)
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
				target = "",
			}
			local state = { origin_pane_id = "%0", session_id = "$1", instances = {}, panes = { target } }

			local ok = state_module.adopt(target, state, "terminal")

			assert.is_true(ok)
			assert.is_true(target.managed)
			assert.are.equal("terminal", target.target)
			assert.are.equal(1, #state.instances)
			assert.are.equal("@wiremux_target", captured_cmds[1][5])
			assert.are.equal("terminal", captured_cmds[1][6])
			assert.are.equal("@wiremux_kind", captured_cmds[2][5])
			assert.are.equal("@wiremux_origin", captured_cmds[3][5])
		end)

		it("does not mutate the target or state when execution fails", function()
			local target = {
				id = "%2",
				window_id = "@1",
				kind = "pane",
				managed = false,
				origin = "%8",
				origin_cwd = "/old",
				last_used_at = 10,
			}
			local state = { origin_pane_id = "%0", last_used_target_id = "%9", instances = {}, panes = { target } }
			local before_target, before_state = vim.deepcopy(target), vim.deepcopy(state)
			local executed = false
			client.execute = function()
				executed = true
				assert.are.same(before_target, target)
				assert.are.same(before_state, state)
				return nil
			end

			assert.is_nil(state_module.adopt(target, state))
			assert.is_true(executed)
			assert.are.same(before_target, target)
			assert.are.same(before_state, state)
		end)
	end)
end)
