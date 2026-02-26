---@module 'luassert'

local helpers = require("tests.helpers_operation")

describe("action.send_keys", function()
	local action = require("wiremux.backend.tmux.action")

	it("accepts single string key", function()
		assert.are.same({ "send-keys", "-t", "%1", "Enter" }, action.send_keys("%1", "Enter"))
	end)

	it("accepts array of keys", function()
		assert.are.same({ "send-keys", "-t", "%1", "i", "Enter" }, action.send_keys("%1", { "i", "Enter" }))
	end)

	it("accepts modifier keys", function()
		assert.are.same({ "send-keys", "-t", "%1", "C-c" }, action.send_keys("%1", "C-c"))
	end)
end)

describe("tmux operations", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	describe("send", function()
		it("sends text to single target", function()
			local executed = false
			mocks.client.execute = function(_, opts)
				executed = true
				assert.are.equal("test text", opts.stdin)
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			local st = { instances = {}, last_used_target_id = nil }

			mocks.operation.send("test text", targets, {}, st)
			assert.is_true(executed)
		end)

		it("cleans tabs and trailing newlines", function()
			local cleaned_text
			mocks.client.execute = function(_, opts)
				cleaned_text = opts.stdin
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			mocks.operation.send("text\twith\ttabs\n", targets, {}, {})

			assert.are.equal("text  with  tabs", cleaned_text)
		end)

		it("sends to multiple targets", function()
			local batch_cmds
			mocks.client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = {
				{ id = "%1", kind = "pane", target = "t1" },
				{ id = "%2", kind = "pane", target = "t2" },
			}

			mocks.operation.send("text", targets, {}, { instances = {} })

			local found_load = false
			local found_paste_count = 0
			local found_delete = false

			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "load-buffer" then
					found_load = true
				elseif cmd[1] == "paste-buffer" then
					found_paste_count = found_paste_count + 1
				elseif cmd[1] == "delete-buffer" then
					found_delete = true
				end
			end

			assert.is_true(found_load)
			assert.are.equal(2, found_paste_count)
			assert.is_true(found_delete)
		end)

		it("handles send failure", function()
			local error_called = false
			mocks.client.execute = function()
				return nil
			end
			mocks.notify.error = function(msg)
				error_called = true
				assert.matches("Failed", msg)
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			mocks.operation.send("text", targets, {}, {})

			assert.is_true(error_called)
		end)

		it("updates last_used_target_id for panes and windows", function()
			local batch_cmds
			mocks.client.execute = function(cmds)
				batch_cmds = cmds
				return "ok"
			end

			local st = { instances = {}, last_used_target_id = nil }
			mocks.operation.send("text", { { id = "%1", kind = "pane", target = "test" } }, {}, st)

			local found_pane = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "set-option" and cmd[5] == "@wiremux_last_used_at" then
					found_pane = true
					break
				end
			end
			assert.is_true(found_pane)

			batch_cmds = nil
			mocks.operation.send("text", { { id = "@1", kind = "window", target = "test" } }, {}, st)

			local found_window = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "set-option" and cmd[5] == "@wiremux_last_used_at" then
					found_window = true
					break
				end
			end
			assert.is_true(found_window)
		end)

		it("skips last_used_at update when target is already last used", function()
			local batch_cmds
			mocks.client.execute = function(cmds)
				batch_cmds = cmds
				return "ok"
			end

			local st = { instances = {}, last_used_target_id = "%1" }
			mocks.operation.send("text", { { id = "%1", kind = "pane", target = "test" } }, {}, st)

			local found_last_used = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "set-option" and cmd[5] == "@wiremux_last_used_at" then
					found_last_used = true
					break
				end
			end
			assert.is_false(found_last_used)
		end)

		it("respects submit option", function()
			local batch_cmds
			mocks.client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			local st = { instances = {}, last_used_target_id = nil }

			mocks.operation.send("text", targets, { submit = true }, st)
			local found_send_keys = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "send-keys" then
					found_send_keys = true
					break
				end
			end
			assert.is_true(found_send_keys)

			batch_cmds = nil
			mocks.operation.send("text", targets, { submit = false }, st)
			found_send_keys = false
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "send-keys" then
					found_send_keys = true
					break
				end
			end
			assert.is_false(found_send_keys)
		end)
	end)

	describe("send submit", function()
		it("sends explicit Enter keystroke", function()
			local batch_cmds
			mocks.client.execute = function(batch, _)
				batch_cmds = batch
				return "ok"
			end

			local targets = { { id = "%1", kind = "pane", target = "test" } }
			local st = { instances = {}, last_used_target_id = "%1" }

			mocks.operation.send("text", targets, { submit = true }, st)

			local send_keys_cmd
			for _, cmd in ipairs(batch_cmds) do
				if cmd[1] == "send-keys" then
					send_keys_cmd = cmd
					break
				end
			end
			assert.are.same({ "send-keys", "-t", "%1", "Enter" }, send_keys_cmd)
		end)
	end)

	describe("create", function()
		it("uses def.title for window name when provided", function()
			local captured_cmds
			mocks.client.execute = function(cmds)
				captured_cmds = cmds
				return "@99"
			end

			local st = { instances = {}, origin_pane_id = "%0" }
			local def = { kind = "window", title = "My Title", label = "My Label" }

			mocks.operation.create("myapp", def, st)

			local new_window_cmd = captured_cmds[1]
			assert.are.equal("new-window", new_window_cmd[1])
			assert.are.equal("-n", new_window_cmd[2])
			assert.are.equal("My Title", new_window_cmd[3])
		end)

		it("falls back to string label for window name when no title", function()
			local captured_cmds
			mocks.client.execute = function(cmds)
				captured_cmds = cmds
				return "@99"
			end

			local st = { instances = {}, origin_pane_id = "%0" }
			local def = { kind = "window", label = "My Label" }

			mocks.operation.create("myapp", def, st)

			local new_window_cmd = captured_cmds[1]
			assert.are.equal("My Label", new_window_cmd[3])
		end)

		it("falls back to target_name when no title or label", function()
			local captured_cmds
			mocks.client.execute = function(cmds)
				captured_cmds = cmds
				return "@99"
			end

			local st = { instances = {}, origin_pane_id = "%0" }
			local def = { kind = "window" }

			mocks.operation.create("myapp", def, st)

			local new_window_cmd = captured_cmds[1]
			assert.are.equal("myapp", new_window_cmd[3])
		end)

		it("sends cmd with Enter for shell targets", function()
			local shell_cmds
			local call_count = 0

			mocks.client.execute = function(cmds)
				call_count = call_count + 1
				if call_count == 1 then
					return "%5"
				else
					shell_cmds = cmds
					return "ok"
				end
			end

			local st = { instances = {}, origin_pane_id = "%0" }
			local def = { kind = "pane", shell = true, cmd = "npm start" }

			mocks.operation.create("myapp", def, st)

			assert.are.same({ { "send-keys", "-t", "%5", "npm start", "Enter" } }, shell_cmds)
		end)

		it("ignores function label for window name", function()
			local captured_cmds
			mocks.client.execute = function(cmds)
				captured_cmds = cmds
				return "@99"
			end

			local st = { instances = {}, origin_pane_id = "%0" }
			local def = {
				kind = "window",
				label = function()
					return "dynamic"
				end,
			}

			mocks.operation.create("myapp", def, st)

			local new_window_cmd = captured_cmds[1]
			assert.are.equal("myapp", new_window_cmd[3])
		end)
	end)
end)
