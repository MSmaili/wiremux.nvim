local helpers = require("tests.helpers")

local M = {}

local MODULES = {
	"wiremux.action.send",
	"wiremux.backend",
	"wiremux.backend.tmux",
	"wiremux.core.action",
	"wiremux.config",
	"wiremux.picker",
	"wiremux.utils.notify",
	"wiremux.context",
	"wiremux.context.input",
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
			},
		}),
		picker = helpers.mock_picker(),
		notify = helpers.mock_notify(),
		context = {
			expand = function(text)
				return text
			end,
		},
		input = {
			find = function()
				return {}
			end,
			has_inputs = function()
				return false
			end,
			replace = function(text)
				return text
			end,
			resolve = function(keys, on_done)
				on_done({})
			end,
			parse = function(key)
				return "Input", nil
			end,
		},
	}

	helpers.register({
		["wiremux.backend"] = {
			get = function()
				return mocks.backend
			end,
		},
		["wiremux.backend.tmux"] = mocks.backend,
		["wiremux.core.action"] = mocks.action,
		["wiremux.config"] = mocks.config,
		["wiremux.picker"] = mocks.picker,
		["wiremux.utils.notify"] = mocks.notify,
		["wiremux.context"] = mocks.context,
		["wiremux.context.input"] = mocks.input,
	})

	mocks.send = require("wiremux.action.send")
	return mocks
end

function M.teardown()
	helpers.clear(MODULES)
end

return M
