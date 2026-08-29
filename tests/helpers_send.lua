local helpers = require("tests.helpers")

local M = {}

local MODULES = {
	"wiremux.action.send",
	"wiremux.action.send.delivery",
	"wiremux.action.send.request",
	"wiremux.history",
	"wiremux.backend",
	"wiremux.core.action",
	"wiremux.config",
	"wiremux.picker",
	"wiremux.utils.notify",
	"wiremux.context",
	"wiremux.ui.compose",
}

function M.setup()
	helpers.clear(MODULES)

	local mocks = {
		backend = helpers.mock_backend({ send = function() end }),
		action = {
			run = function(opts, callbacks)
				if callbacks.on_targets then
					callbacks.on_targets({}, {})
				end
			end,
		},
		config = helpers.mock_config({
			send = {
				focus = false,
				behavior = "pick",
				submit = false,
				compose = false,
			},
		}),
		picker = helpers.mock_picker(),
		notify = helpers.mock_notify(),
		context = {
			capture_origin = function()
				return { bufnr = 1, path = "/source.lua", row = 1, col = 0, selection = "", line = "" }
			end,
			resolve = function(text)
				return text
			end,
			get = function(name)
				return name
			end,
		},
		compose = {
			get_buf = function()
				return nil
			end,
			open = function() end,
		},
		history = {
			add = function()
				return true
			end,
		},
	}

	helpers.register({
		["wiremux.backend"] = {
			get = function()
				return mocks.backend
			end,
		},
		["wiremux.core.action"] = mocks.action,
		["wiremux.config"] = mocks.config,
		["wiremux.picker"] = mocks.picker,
		["wiremux.utils.notify"] = mocks.notify,
		["wiremux.context"] = mocks.context,
		["wiremux.ui.compose"] = mocks.compose,
		["wiremux.history"] = mocks.history,
	})

	mocks.send = require("wiremux.action.send")
	return mocks
end

function M.teardown()
	helpers.clear(MODULES)
end

return M
