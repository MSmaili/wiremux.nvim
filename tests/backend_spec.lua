---@module 'luassert'

local helpers = require("tests.helpers")

describe("backend", function()
	local modules = {
		"wiremux.backend",
		"wiremux.backend.tmux",
		"wiremux.utils.notify",
	}

	local original_tmux_env

	before_each(function()
		original_tmux_env = vim.env.TMUX
		helpers.clear(modules)
	end)

	after_each(function()
		vim.env.TMUX = original_tmux_env
		helpers.clear(modules)
	end)

	it("returns tmux backend when inside tmux", function()
		local tmux_backend = { name = "tmux" }
		vim.env.TMUX = "/tmp/tmux-1000/default,123,0"

		helpers.register({
			["wiremux.backend.tmux"] = tmux_backend,
		})

		local backend = require("wiremux.backend")

		assert.are.equal(tmux_backend, backend.get())
	end)

	it("notifies when no supported backend is active", function()
		local notified = false
		vim.env.TMUX = nil

		helpers.register({
			["wiremux.utils.notify"] = {
				error = function(msg)
					notified = true
					assert.matches("supported backend", msg)
				end,
			},
		})

		local backend = require("wiremux.backend")

		assert.is_nil(backend.get())
		assert.is_true(notified)
	end)
end)
