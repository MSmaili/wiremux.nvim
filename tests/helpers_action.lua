local helpers = require("tests.helpers")

local M = {}

local MODULES = {
	"wiremux.core.action",
	"wiremux.backend.tmux",
	"wiremux.core.resolver",
	"wiremux.config",
	"wiremux.picker",
	"wiremux.utils.notify",
}

function M.setup()
	helpers.clear(MODULES)

	local mocks = {
		backend = helpers.mock_backend(),
		resolver = helpers.mock_resolver(),
		config = helpers.mock_config(),
		picker = helpers.mock_picker(),
		notify = helpers.mock_notify(),
	}

	helpers.register({
		["wiremux.backend.tmux"] = mocks.backend,
		["wiremux.core.resolver"] = mocks.resolver,
		["wiremux.config"] = mocks.config,
		["wiremux.picker"] = mocks.picker,
		["wiremux.utils.notify"] = mocks.notify,
	})

	mocks.action = require("wiremux.core.action")
	return mocks
end

function M.teardown()
	helpers.clear(MODULES)
end

return M
