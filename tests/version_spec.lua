---@module 'luassert'

describe("supported neovim version", function()
	local version

	before_each(function()
		package.loaded["wiremux.version"] = nil
		version = require("wiremux.version")
	end)

	after_each(function()
		package.loaded["wiremux.version"] = nil
	end)

	it("declares the floor in one place and accepts the running version", function()
		assert.are.equal("0.11", version.MIN_NVIM)
		assert.is_true(version.supported())
	end)

	it("reports the floor and the running version when the floor is not met", function()
		version.MIN_NVIM = "99.0"

		assert.is_false(version.supported())
		assert.matches("requires Neovim 99%.0 or later", version.requirement())
		assert.matches(tostring(vim.version()), version.requirement(), 1, true)
	end)
end)
