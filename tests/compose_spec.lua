---@module 'luassert'

describe("compose UI", function()
	local compose
	local config
	local event_group

	local function mapping(key)
		return vim.fn.maparg(key, "n", false, true).callback
	end

	local function title()
		local value = vim.api.nvim_win_get_config(0).title
		return type(value) == "table" and value[1][1] or value
	end

	local function open(text, opts)
		opts = opts or {}
		local selected = opts.compose == nil and true or opts.compose
		local resolved, errors = require("wiremux.utils.validate").resolve_compose(
			config.opts.ui.compose,
			selected,
			"test.compose"
		)
		assert.are.same({}, errors)

		local open_opts = { config = resolved }
		for key, value in pairs(opts) do
			if key ~= "compose" then
				open_opts[key] = value
			end
		end
		return compose.open(text, open_opts)
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
		event_group = vim.api.nvim_create_augroup("wiremux_compose_test_user", { clear = true })
		compose = require("wiremux.ui.compose")
	end)

	after_each(function()
		local buf = compose.get_buf()
		if buf then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		pcall(vim.api.nvim_del_augroup_by_id, event_group)
	end)

	it("appends pages, saves edits, navigates, and confirms in order", function()
		local confirmed_pages
		local cancelled = false
		open("first", {
			page_meta = "one",
			on_confirm = function()
				error("old callback should be replaced")
			end,
		})
		local buf = compose.get_buf()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited first" })

		open("second", {
			compose = { title = " Review " },
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
		open("first", {
			on_confirm = function()
				calls = calls + 1
				return false
			end,
		})
		open("second", {
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
		open("draft", {
			compose = { title = " Original " },
			on_confirm = function(pages)
				first_called = pages[1].text == "draft"
				return true
			end,
		})
		mapping("q")()

		open("", {
			compose = { title = " Ignored " },
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
		open("   ", { on_confirm = function() end })
		open("replacement", {
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
		open("first", {
			compose = { title = " First Title " },
			on_confirm = function()
				error("old callback should be replaced")
			end,
		})
		open("ignored", {
			compose = { title = " Latest Title " },
			on_confirm = function(pages)
				latest_called = pages[1].text == "first" and #pages == 1
				return true
			end,
		})

		assert.matches("Latest Title", title())
		mapping("<CR>")()
		assert.is_true(latest_called)
	end)

	it("merges per-session compose options over global defaults", function()
		config.opts.ui.compose.on_new_payload = "keep"
		config.opts.ui.compose.close_behavior = "ask"
		local pages
		local compose_config = {
			on_new_payload = "append",
			close_behavior = "hide",
		}

		open("first", {
			compose = compose_config,
			on_confirm = function() end,
		})
		open("second", {
			compose = compose_config,
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(2, #pages)
		assert.are.equal("first", pages[1].text)
		assert.are.equal("second", pages[2].text)
		assert.are.equal("keep", config.opts.ui.compose.on_new_payload)
		assert.are.equal("ask", config.opts.ui.compose.close_behavior)
	end)

	it("invokes cancellation once when the draft buffer is wiped", function()
		local cancelled = 0
		open("draft", {
			on_confirm = function() end,
			on_cancel = function()
				cancelled = cancelled + 1
			end,
		})
		vim.api.nvim_buf_delete(compose.get_buf(), { force = true })

		assert.are.equal(1, cancelled)
		assert.is_nil(compose.get_buf())
	end)

	it("emits WiremuxComposeOpen when opening and reopening the window", function()
		local events = {}
		vim.api.nvim_create_autocmd("User", {
			group = event_group,
			pattern = "WiremuxComposeOpen",
			callback = function(event)
				table.insert(events, vim.deepcopy(event.data))
				assert.is_true(vim.api.nvim_buf_is_valid(event.data.buf))
				assert.is_true(vim.api.nvim_win_is_valid(event.data.win))
				assert.are.equal(event.data.win, vim.api.nvim_get_current_win())
				vim.wo[event.data.win].spell = true
			end,
		})

		open("first", { on_confirm = function() end })
		local buf = compose.get_buf()
		assert.are.equal(1, #events)
		assert.is_false(events[1].reopened)
		assert.are.equal(buf, events[1].buf)
		assert.is_true(vim.wo[events[1].win].spell)

		open("second", { on_confirm = function() end })
		assert.are.equal(1, #events)
		mapping("q")()
		open("", { on_confirm = function() end })

		assert.are.equal(2, #events)
		assert.is_true(events[2].reopened)
		assert.are.equal(buf, events[2].buf)
	end)

	it("keeps compose usable when WiremuxComposeOpen fails", function()
		local exec_autocmds = vim.api.nvim_exec_autocmds
		local notify = require("wiremux.utils.notify")
		local notify_error = notify.error
		vim.api.nvim_exec_autocmds = function()
			error("custom setup failed")
		end
		notify.error = function() end
		local ok = pcall(open, "draft", { on_confirm = function() end })
		vim.api.nvim_exec_autocmds = exec_autocmds
		notify.error = notify_error

		assert.is_true(ok)
		assert.is_true(vim.api.nvim_buf_is_valid(compose.get_buf()))
	end)
end)
