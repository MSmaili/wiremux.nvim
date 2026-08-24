---@module 'luassert'

local helpers = require("tests.helpers")

describe("picker single-fire contract", function()
	local picker

	before_each(function()
		helpers.clear({ "wiremux.picker", "wiremux.config" })
		picker = require("wiremux.picker")
		picker.reset()
	end)

	after_each(function()
		helpers.clear({ "wiremux.picker", "wiremux.config" })
	end)

	---Adapters may fire more than once; callers must still see at most one call.
	---@param adapter function
	local function use_adapter(adapter)
		require("wiremux.config").setup({ log_level = "off", picker = { adapter = adapter } })
		picker.reset()
	end

	it("delivers at most one selection from a repeating select adapter", function()
		local choices = {}
		use_adapter(function(items, _, on_choice)
			on_choice(items[1])
			on_choice(items[2])
			on_choice(nil)
		end)

		picker.select({ "first", "second" }, {}, function(choice)
			table.insert(choices, choice)
		end)

		assert.are.same({ "first" }, choices)
	end)

	it("delivers at most one cancellation from a repeating select adapter", function()
		local calls = 0
		use_adapter(function(_, _, on_choice)
			on_choice(nil)
			on_choice(nil)
		end)

		picker.select({ "only" }, {}, function()
			calls = calls + 1
		end)

		assert.are.equal(1, calls)
	end)

	it("delivers at most one path from a repeating files adapter", function()
		local original = package.loaded["wiremux.picker.fzf-lua"]
		package.loaded["wiremux.picker.fzf-lua"] = {
			available = function()
				return true
			end,
			select = function(_, _, on_choice)
				on_choice(nil)
			end,
			files = function(_, on_choice)
				on_choice("/first.lua")
				on_choice("/second.lua")
			end,
		}
		require("wiremux.config").setup({ log_level = "off" })
		picker.reset()
		local paths = {}

		picker.files({}, function(path)
			table.insert(paths, path)
		end)

		package.loaded["wiremux.picker.fzf-lua"] = original
		assert.are.same({ "/first.lua" }, paths)
	end)
end)
