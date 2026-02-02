---@module 'luassert'

describe("tmux operations", function()
	local operation, client, state, notify, action

	before_each(function()
		-- Clear loaded modules
		package.loaded["wiremux.backend.tmux.client"] = nil
		package.loaded["wiremux.backend.tmux.state"] = nil
		package.loaded["wiremux.utils.notify"] = nil
		package.loaded["wiremux.backend.tmux.action"] = nil
		package.loaded["wiremux.backend.tmux.operation"] = nil

		-- Mock action module
		action = {
			load_buffer = function(name)
				return { "load-buffer", "-b", name, "-" }
			end,
			paste_buffer = function(name, target)
				return { "paste-buffer", "-b", name, "-p", "-t", target }
			end,
			delete_buffer = function(name)
				return { "delete-buffer", "-b", name }
			end,
			select_window = function(id)
				return { "select-window", "-t", id }
			end,
			select_pane = function(id)
				return { "select-pane", "-t", id }
			end,
			set_pane_option = function(pane_id, key, value)
				return { "set-option", "-p", "-t", pane_id, key, value }
			end,
			send_keys = function(target, keys)
				return { "send-keys", "-t", target, keys, "Enter" }
			end,
		}

		-- Mock client
		client = {
			execute = function()
				return "ok"
			end,
		}

		-- Mock state
		state = {
			update_last_used = function(batch, old_id, new_id)
				-- Append to batch like the real function
				if old_id and old_id ~= new_id then
					table.insert(batch, action.set_pane_option(old_id, "@wiremux_last_used", "false"))
				end
				table.insert(batch, action.set_pane_option(new_id, "@wiremux_last_used", "true"))
			end,
			set_instance_metadata = function() end,
		}

		-- Mock notify
		notify = {
			debug = function() end,
			error = function() end,
		}

		-- Set up mocks
		package.loaded["wiremux.backend.tmux.action"] = action
		package.loaded["wiremux.backend.tmux.client"] = client
		package.loaded["wiremux.backend.tmux.state"] = state
		package.loaded["wiremux.utils.notify"] = notify

		-- Load operation module
		operation = require("wiremux.backend.tmux.operation")
	end)

	describe("send", function()
		it("sends text to single target", function()
			local executed = false
			client.execute = function(_, opts)
				executed = true
				assert.are.equal("test text", opts.stdin)
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			local st = { instances = {}, last_used_target_id = nil }

			operation.send("test text", targets, {}, st)
			assert.is_true(executed)
		end)

		it("cleans tabs and trailing newlines", function()
			local cleaned_text
			client.execute = function(_, opts)
				cleaned_text = opts.stdin
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			operation.send("text\twith\ttabs\n", targets, {}, {})

			assert.are.equal("text  with  tabs", cleaned_text)
		end)

		it("sends to multiple targets", function()
			local batch_cmds
			client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = {
				{ id = "%1", kind = "pane", target = "t1" },
				{ id = "%2", kind = "pane", target = "t2" },
			}

			operation.send("text", targets, {}, { instances = {} })

			assert.are.equal(5, #batch_cmds)

			-- Verify exact batch commands (IPC call structure)
			assert.are.same({ "load-buffer", "-b", "wiremux", "-" }, batch_cmds[1])
			assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%1" }, batch_cmds[2])
			assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%2" }, batch_cmds[3])
			assert.are.same({ "delete-buffer", "-b", "wiremux" }, batch_cmds[4])
			assert.are.equal("set-option", batch_cmds[5][1])
		end)

		it("handles send failure", function()
			local error_called = false
			client.execute = function()
				return nil
			end
			notify.error = function(msg)
				error_called = true
				assert.matches("Failed", msg)
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			operation.send("text", targets, {}, {})

			assert.is_true(error_called)
		end)

		it("updates last_used_target_id", function()
			local batch_cmds
			client.execute = function(cmds)
				batch_cmds = cmds
				return "ok"
			end

			local st = { instances = {}, last_used_target_id = nil }
			local targets = { { id = "%1", kind = "pane", target = "test" } }

			operation.send("text", targets, {}, st)

			-- Verify set_pane_option was called for last_used
			local found = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "set-option" and cmd[5] == "@wiremux_last_used" then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)

		it("updates last_used_target_id for windows", function()
			local batch_cmds
			client.execute = function(cmds)
				batch_cmds = cmds
				return "ok"
			end

			local st = { instances = {}, last_used_target_id = nil }
			local targets = { { id = "@1", kind = "window", target = "test" } }

			operation.send("text", targets, {}, st)

			-- Verify set_pane_option was called for last_used
			local found = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "set-option" and cmd[5] == "@wiremux_last_used" then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)

		it("sends Enter key when submit=true", function()
			local batch_cmds
			client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			local st = { instances = {}, last_used_target_id = nil }

			operation.send("text", targets, { submit = true }, st)

			-- Should have: load, paste, send-keys, delete, set-state
			assert.are.equal(5, #batch_cmds)
			assert.are.same({ "load-buffer", "-b", "wiremux", "-" }, batch_cmds[1])
			assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%1" }, batch_cmds[2])
			assert.are.same({ "send-keys", "-t", "%1", "", "Enter" }, batch_cmds[3])
			assert.are.same({ "delete-buffer", "-b", "wiremux" }, batch_cmds[4])
		end)

		it("does not send Enter key when submit=false", function()
			local batch_cmds
			client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			local st = { instances = {}, last_used_target_id = nil }

			operation.send("text", targets, { submit = false }, st)

			-- Should have: load, paste, delete, set-last-used (no send-keys)
			assert.are.equal(4, #batch_cmds)
			assert.are.same({ "load-buffer", "-b", "wiremux", "-" }, batch_cmds[1])
			assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%1" }, batch_cmds[2])
			assert.are.same({ "delete-buffer", "-b", "wiremux" }, batch_cmds[3])
		end)

		it("sends Enter to multiple targets when submit=true", function()
			local batch_cmds
			client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = {
				{ id = "%1", kind = "pane", target = "t1" },
				{ id = "%2", kind = "pane", target = "t2" },
			}

			operation.send("text", targets, { submit = true }, { instances = {} })

			-- Should have: load, paste1, send-keys1, paste2, send-keys2, delete, set-last-used
			assert.are.equal(7, #batch_cmds)
			assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%1" }, batch_cmds[2])
			assert.are.same({ "send-keys", "-t", "%1", "", "Enter" }, batch_cmds[3])
			assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%2" }, batch_cmds[4])
			assert.are.same({ "send-keys", "-t", "%2", "", "Enter" }, batch_cmds[5])
		end)
	end)
end)
