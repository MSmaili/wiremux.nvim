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

describe("picker payload previews", function()
	local module_names = {
		"fzf-lua",
		"fzf-lua.config",
		"fzf-lua.utils",
		"snacks",
		"wiremux.picker.fzf-lua",
		"wiremux.picker.snacks",
	}
	local originals

	before_each(function()
		originals = {}
		for _, name in ipairs(module_names) do
			originals[name] = package.loaded[name]
			package.loaded[name] = nil
		end
	end)

	after_each(function()
		for _, name in ipairs(module_names) do
			package.loaded[name] = originals[name]
		end
	end)

	it("uses fzf-lua's configured file previewer", function()
		local lines
		local picker_opts
		local configured_previewer = {}
		package.loaded["fzf-lua"] = {
			fzf_exec = function(input, opts)
				lines = input
				picker_opts = opts
			end,
		}
		package.loaded["fzf-lua.config"] = { globals = { files = { previewer = configured_previewer } } }
		package.loaded["fzf-lua.utils"] = { nbsp = "<path>" }
		local items = { { file = "first.txt" }, { file = "second.txt" } }

		require("wiremux.picker.fzf-lua").select(items, {
			format_item = function(item)
				return item.file:upper()
			end,
			preview_file = function(item)
				return "/history/" .. item.file
			end,
		}, function() end)

		assert.are.equal(configured_previewer, picker_opts.previewer)
		assert.are.same({
			"1\tFIRST.TXT\t<path>/history/first.txt",
			"2\tSECOND.TXT\t<path>/history/second.txt",
		}, lines)
		assert.are.equal("2..-2", picker_opts.fzf_opts["--with-nth"])
		assert.are.equal("1..", picker_opts.fzf_opts["--nth"])
	end)

	it("uses Snacks' native file preview item", function()
		local picker_items
		local select_opts
		local select_choice
		package.loaded["snacks"] = {
			picker = {
				select = function(items, opts, on_choice)
					picker_items = items
					select_opts = opts
					select_choice = on_choice
				end,
			},
		}
		local item = { file = "entry.txt" }
		local selected

		require("wiremux.picker.snacks").select({ item }, {
			format_item = function(choice)
				return choice.file
			end,
			preview_file = function(choice)
				assert.are.equal(item, choice)
				return "/history/entry.txt"
			end,
		}, function(choice)
			selected = choice
		end)

		assert.are.equal("/history/entry.txt", picker_items[1].file)
		assert.are.equal("entry.txt", select_opts.format_item(picker_items[1]))
		assert.are.equal("file", select_opts.snacks.preview)
		select_choice(picker_items[1])
		assert.are.equal(item, selected)
	end)
end)
