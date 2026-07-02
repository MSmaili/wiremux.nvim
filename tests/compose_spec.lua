---@module 'luassert'

describe("compose UI", function()
	local compose
	local config

	local function mapping(key)
		return vim.fn.maparg(key, "n", false, true).callback
	end

	local function title()
		local value = vim.api.nvim_win_get_config(0).title
		return type(value) == "table" and value[1][1] or value
	end

	before_each(function()
		package.loaded["wiremux.ui.compose"] = nil
		package.loaded["wiremux.config"] = nil
		config = require("wiremux.config")
		config.setup({
			ui = {
				compose = {
					on_new_payload = "append",
					close_behavior = "hide",
				},
			},
		})
		compose = require("wiremux.ui.compose")
	end)

	after_each(function()
		local buf = compose.get_buf()
		if buf then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end)

	it("appends pages, saves edits, navigates, and confirms in order", function()
		local confirmed_pages
		local cancelled = false
		compose.open("first", {
			page_meta = "one",
			on_confirm = function()
				error("old callback should be replaced")
			end,
		})
		local buf = compose.get_buf()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited first" })

		compose.open("second", {
			title = " Review ",
			page_meta = "two",
			on_confirm = function(pages)
				confirmed_pages = vim.deepcopy(pages)
				return true
			end,
			on_cancel = function()
				cancelled = true
			end,
		})

		assert.are.equal("second", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		mapping("<C-p>")()
		assert.are.equal("edited first", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		assert.matches("Review%s+%[1/2%]", title())
		vim.cmd("silent undo")
		assert.are.equal("edited first", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		mapping("<C-n>")()
		mapping("<CR>")()

		assert.are.same({
			{ text = "edited first", meta = "one" },
			{ text = "second", meta = "two" },
		}, confirmed_pages)
		assert.is_nil(compose.get_buf())
		assert.is_false(cancelled)
	end)

	it("preserves the complete draft when confirmation fails", function()
		local calls = 0
		compose.open("first", {
			on_confirm = function()
				calls = calls + 1
				return false
			end,
		})
		compose.open("second", {
			on_confirm = function()
				calls = calls + 1
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(1, calls)
		assert.is_true(vim.api.nvim_buf_is_valid(compose.get_buf()))
		assert.matches("%[2/2%]", title())
	end)

	it("treats an empty invocation as reopen only", function()
		local first_called = false
		local empty_called = false
		compose.open("draft", {
			title = " Original ",
			on_confirm = function(pages)
				first_called = pages[1].text == "draft"
				return true
			end,
		})
		mapping("q")()

		compose.open("", {
			title = " Ignored ",
			on_confirm = function()
				empty_called = true
				return true
			end,
		})
		assert.matches("Original", title())
		mapping("<CR>")()

		assert.is_true(first_called)
		assert.is_false(empty_called)
	end)

	it("reuses an entirely empty draft instead of appending", function()
		local pages
		compose.open("   ", { on_confirm = function() end })
		compose.open("replacement", {
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(1, #pages)
		assert.are.equal("replacement", pages[1].text)
		assert.not_matches("%[", title())
	end)

	it("updates callbacks and title while keeping existing content", function()
		config.opts.ui.compose.on_new_payload = "keep"
		local latest_called = false
		compose.open("first", {
			title = " First Title ",
			on_confirm = function()
				error("old callback should be replaced")
			end,
		})
		compose.open("ignored", {
			title = " Latest Title ",
			on_confirm = function(pages)
				latest_called = pages[1].text == "first" and #pages == 1
				return true
			end,
		})

		assert.matches("Latest Title", title())
		mapping("<CR>")()
		assert.is_true(latest_called)
	end)

	it("invokes cancellation once when the draft buffer is wiped", function()
		local cancelled = 0
		compose.open("draft", {
			on_confirm = function() end,
			on_cancel = function()
				cancelled = cancelled + 1
			end,
		})
		vim.api.nvim_buf_delete(compose.get_buf(), { force = true })

		assert.are.equal(1, cancelled)
		assert.is_nil(compose.get_buf())
	end)
end)
