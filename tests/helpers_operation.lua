local helpers = require("tests.helpers")

local M = {}

local MODULES = {
	"wiremux.backend.tmux.client",
	"wiremux.backend.tmux.state",
	"wiremux.backend.tmux.query",
	"wiremux.utils.notify",
	"wiremux.backend.tmux.action",
	"wiremux.backend.tmux.operation",
}

function M.setup()
	helpers.clear(MODULES)

	local mocks = {
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
			new_window = function(name, command)
				local cmd = { "new-window" }
				if name then
					vim.list_extend(cmd, { "-n", name })
				end
				if command then
					table.insert(cmd, command)
				end
				return cmd
			end,
			split_pane = function(direction, target_pane, command)
				local cmd = { "split-window", direction == "horizontal" and "-h" or "-v" }
				if target_pane then
					vim.list_extend(cmd, { "-t", target_pane })
				end
				if command then
					table.insert(cmd, command)
				end
				return cmd
			end,
		},
		query = {
			window_id = function()
				return { "display", "-p", "#{window_id}" }
			end,
			pane_id = function()
				return { "display", "-p", "#{pane_id}" }
			end,
		},
		client = {
			execute = function()
				return "ok"
			end,
		},
		notify = helpers.mock_notify(),
	}

	mocks.state = {
		update_last_used = function(batch, new_id)
			table.insert(batch, mocks.action.set_pane_option(new_id, "@wiremux_last_used_at", tostring(1234567890)))
		end,
		set_instance_metadata = function() end,
	}

	helpers.register({
		["wiremux.backend.tmux.action"] = mocks.action,
		["wiremux.backend.tmux.client"] = mocks.client,
		["wiremux.backend.tmux.state"] = mocks.state,
		["wiremux.backend.tmux.query"] = mocks.query,
		["wiremux.utils.notify"] = mocks.notify,
	})

	mocks.operation = require("wiremux.backend.tmux.operation")
	return mocks
end

function M.teardown()
	helpers.clear(MODULES)
end

return M
