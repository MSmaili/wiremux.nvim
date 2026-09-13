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

	local action = require("wiremux.backend.tmux.action")
	local mocks = {
		client = {
			execute = function()
				return "ok"
			end,
		},
		notify = helpers.mock_notify(),
	}

	mocks.state = {
		update_last_used = function(batch, new_id)
			table.insert(batch, action.set_pane_option(new_id, "@wiremux_last_used_at", tostring(1234567890)))
		end,
		adopt = function()
			return true
		end,
		set_instance_metadata = function() end,
	}

	helpers.register({
		["wiremux.backend.tmux.client"] = mocks.client,
		["wiremux.backend.tmux.state"] = mocks.state,
		["wiremux.utils.notify"] = mocks.notify,
	})

	mocks.operation = require("wiremux.backend.tmux.operation")
	return mocks
end

function M.teardown()
	helpers.clear(MODULES)
end

return M
