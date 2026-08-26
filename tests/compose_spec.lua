---@module 'luassert'

describe("compose UI", function()
	local compose
	local config
	local event_group

	local function mapping(key, mode)
		return vim.fn.maparg(key, mode or "n", false, true).callback
	end

	local function buffer_mapping(buf, key, mode)
		local result
		vim.api.nvim_buf_call(buf, function()
			result = vim.fn.maparg(key, mode or "n", false, true)
		end)
		return result
	end

	local function decoration_text(value)
		if type(value) == "string" then
			return value
		end
		local parts = {}
		for _, chunk in ipairs(value or {}) do
			table.insert(parts, type(chunk) == "table" and chunk[1] or tostring(chunk))
		end
		return table.concat(parts)
	end

	local function title()
		local value = vim.api.nvim_win_get_config(0).title
		return type(value) == "table" and value[1][1] or value
	end

	local function footer()
		return decoration_text(vim.api.nvim_win_get_config(0).footer)
	end

	local function session_config(overrides)
		overrides = overrides or {}
		local resolved = vim.tbl_deep_extend("force", {}, config.opts.ui.compose, overrides)
		if overrides.keymaps ~= nil then
			resolved.keymaps = vim.deepcopy(overrides.keymaps)
		end
		if overrides.wo ~= nil then
			resolved.wo = vim.deepcopy(overrides.wo)
		end
		return resolved
	end

	local function open_resolved(text, overrides, opts)
		opts = opts or {}
		compose.open(text, {
			config = session_config(overrides),
			source = opts.source,
			on_confirm = opts.on_confirm or function() end,
			on_preview = opts.on_preview,
			on_cancel = opts.on_cancel,
		})
	end

	local function open(text, opts)
		opts = opts or {}
		local selected = opts.compose == nil and true or opts.compose
		local resolved, errors =
			require("wiremux.ui.compose.config").resolve(config.opts.ui.compose, selected, "test.compose")
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
		package.loaded["wiremux.ui.compose.view"] = nil
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

	it("cannot re-enter confirmation from within on_confirm or after sending", function()
		local confirms = 0
		local send_key
		open("draft", {
			on_confirm = function()
				confirms = confirms + 1
				send_key()
				return true
			end,
		})
		send_key = mapping("<CR>")

		send_key()
		if mapping("<CR>") then
			mapping("<CR>")()
		end

		assert.are.equal(1, confirms)
		assert.is_nil(compose.get_buf())
	end)

	it("appends pages, saves edits, navigates, and confirms sources in order", function()
		local confirmed_pages
		local cancelled = false
		local first_source = { marker = "one" }
		local second_source = { marker = "two" }
		open("first", {
			source = first_source,
			on_confirm = function()
				error("old callback should be replaced")
			end,
		})
		local buf = compose.get_buf()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited first" })

		open("second", {
			compose = { title = " Review " },
			source = second_source,
			on_confirm = function(pages)
				confirmed_pages = pages
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

		assert.are.equal("edited first", confirmed_pages[1].text)
		assert.are.equal(first_source, confirmed_pages[1].source)
		assert.are.equal("second", confirmed_pages[2].text)
		assert.are.equal(second_source, confirmed_pages[2].source)
		assert.is_nil(compose.get_buf())
		assert.is_false(cancelled)
	end)

	it("deletes the current page, wraps forward, and clears the only page", function()
		local sources = { { page = 1 }, { page = 2 }, { page = 3 } }
		local confirmed_pages
		open("first", { source = sources[1], on_confirm = function() end })
		open("second", { source = sources[2], on_confirm = function() end })
		open("third", {
			source = sources[3],
			on_confirm = function(pages)
				confirmed_pages = pages
				return true
			end,
		})
		local buf = assert(compose.get_buf())

		mapping("<C-x>")()
		assert.are.equal("first", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		assert.matches("%[1/2%]", title())

		mapping("<C-x>")()
		assert.are.equal("second", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		assert.is_nil(title():match("%["))

		mapping("<C-x>")()
		assert.are.same({ "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		mapping("<CR>")()

		assert.are.equal(1, #confirmed_pages)
		assert.are.equal("", confirmed_pages[1].text)
		assert.are.equal(sources[2], confirmed_pages[1].source)
	end)

	it("previews the placeholder under the cursor without changing its page", function()
		local source = { marker = "stored" }
		local preview_calls = 0
		local preview_source
		open("Review {changes}", {
			source = source,
			on_preview = function(page_source, name)
				preview_calls = preview_calls + 1
				preview_source = page_source
				assert.are.equal("changes", name)
				return "diff --git a/file b/file", "diff"
			end,
			on_confirm = function()
				return false
			end,
		})
		local compose_buf = assert(compose.get_buf())
		vim.api.nvim_win_set_cursor(0, { 1, 9 })

		mapping("K")()

		local preview_win = vim.b[compose_buf].lsp_floating_preview
		assert.is_true(vim.api.nvim_win_is_valid(preview_win))
		local preview_buf = vim.api.nvim_win_get_buf(preview_win)
		assert.are.same({ "diff --git a/file b/file" }, vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false))
		assert.are.equal("diff", vim.bo[preview_buf].syntax)
		assert.are.same({ "Review {changes}" }, vim.api.nvim_buf_get_lines(compose_buf, 0, -1, false))
		assert.are.equal(source, preview_source)

		mapping("K")()
		assert.are.equal(preview_win, vim.api.nvim_get_current_win())
		mapping("<Esc>")()
		assert.is_false(vim.api.nvim_win_is_valid(preview_win))

		vim.api.nvim_set_current_win(vim.fn.bufwinid(compose_buf))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		mapping("K")()
		assert.are.equal(1, preview_calls)
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

	it("treats an empty invocation as reopen only without replacing its source", function()
		local first_called = false
		local original_source = { marker = "original" }
		open("draft", {
			compose = { title = " Original " },
			source = original_source,
			on_confirm = function(pages)
				first_called = pages[1].text == "draft" and pages[1].source == original_source
				return true
			end,
		})
		mapping("q")()

		compose.open("")
		assert.matches("Original", title())
		mapping("<CR>")()

		assert.is_true(first_called)
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

	it("keeps the existing page source and rejects the incoming source", function()
		config.opts.ui.compose.on_new_payload = "keep"
		local original_source = { marker = "original" }
		local rejected_source = { marker = "rejected" }
		local pages
		open("first", {
			source = original_source,
			on_confirm = function() end,
		})
		open("ignored", {
			source = rejected_source,
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(1, #pages)
		assert.are.equal("first", pages[1].text)
		assert.are.equal(original_source, pages[1].source)
		assert.are_not.equal(rejected_source, pages[1].source)
	end)

	it("replaces all old pages and sources", function()
		config.opts.ui.compose.on_new_payload = "replace"
		local old_source = { marker = "old" }
		local replacement_source = { marker = "replacement" }
		local pages
		open("old", {
			source = old_source,
			on_confirm = function() end,
		})
		open("replacement", {
			source = replacement_source,
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(1, #pages)
		assert.are.equal("replacement", pages[1].text)
		assert.are.equal(replacement_source, pages[1].source)
		assert.are_not.equal(old_source, pages[1].source)
	end)

	it("keeps distinct opaque sources for identical appended text", function()
		local first_source = { future = { marker = "first" } }
		local second_source = { future = { marker = "second" } }
		local pages
		open("same", {
			source = first_source,
			on_confirm = function() end,
		})
		open("same", {
			source = second_source,
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(2, #pages)
		assert.are.equal(first_source, pages[1].source)
		assert.are.equal(second_source, pages[2].source)
		assert.are.same({ marker = "first" }, pages[1].source.future)
		assert.are.same({ marker = "second" }, pages[2].source.future)
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

	it("defaults ask policy to keeping the complete existing draft", function()
		local confirm = vim.fn.confirm
		local prompt_default
		vim.fn.confirm = function(_, _, default)
			prompt_default = default
			return default
		end
		local pages
		open_resolved("first", { on_new_payload = "ask" })
		open_resolved("ignored", { on_new_payload = "ask" }, {
			on_confirm = function(value)
				pages = value
				return false
			end,
		})
		vim.fn.confirm = confirm

		mapping("<CR>")()

		assert.are.equal(1, prompt_default)
		assert.are.equal(1, #pages)
		assert.are.equal("first", pages[1].text)
	end)

	it("appends to a hidden draft and selects the incoming page", function()
		local pages
		local compose_config = {
			on_new_payload = "append",
			close_behavior = "hide",
			keymaps = {
				send = { "<CR>", mode = "n" },
				close = { "q", mode = "n" },
				previous = { "<C-p>", mode = "n" },
			},
		}
		open_resolved("first", compose_config)
		local buf = compose.get_buf()
		mapping("q")()
		assert.are.equal(-1, vim.fn.bufwinid(buf))

		open_resolved("second", compose_config, {
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		assert.are.equal(buf, compose.get_buf())
		assert.are.equal("second", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		assert.matches("%[2/2%]", title())
		mapping("<C-p>")()
		assert.are.equal("first", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		mapping("<CR>")()
		assert.are.equal(2, #pages)
	end)

	it("replaces an entirely whitespace-only multi-page draft", function()
		local pages
		open("first", { on_confirm = function() end })
		open("second", { on_confirm = function() end })
		local buf = compose.get_buf()
		mapping("<C-p>")()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  " })
		mapping("<C-n>")()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "\t" })

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

	it("refreshes geometry, title, footer, border, and window options", function()
		local first_config = {
			width = 0.3,
			height = 0.2,
			title = " First View ",
			on_new_payload = "keep",
			border = "rounded",
			wo = { wrap = true, number = false, spell = true },
			keymaps = {
				send = { "<F5>", mode = "n" },
				close = { "q", mode = "n" },
			},
		}
		open_resolved("draft", first_config)
		local first_window = vim.api.nvim_win_get_config(0)
		local first_border = vim.deepcopy(first_window.border)
		assert.matches("F5", footer())
		assert.is_true(vim.wo[0].spell)

		local second_config = {
			width = 0.7,
			height = 0.5,
			title = " Refreshed View ",
			on_new_payload = "keep",
			border = "single",
			wo = { wrap = false, number = true },
			keymaps = {
				send = { "<F6>", mode = "n" },
			},
		}
		open_resolved("ignored", second_config)
		local refreshed = vim.api.nvim_win_get_config(0)

		assert.are.equal(math.floor(vim.o.columns * 0.7), refreshed.width)
		assert.are.equal(math.floor(vim.o.lines * 0.5), refreshed.height)
		assert.matches("Refreshed View", title())
		assert.are_not.same(first_border, refreshed.border)
		assert.is_false(vim.wo[0].wrap)
		assert.is_true(vim.wo[0].number)
		assert.is_false(vim.wo[0].spell)
		assert.matches("F6", footer())
		assert.not_matches("F5", footer())
	end)

	it("applies refreshed configuration when reopening a hidden session", function()
		local first = {
			width = 0.3,
			title = " Hidden First ",
			on_new_payload = "append",
			close_behavior = "hide",
			wo = { number = false },
			keymaps = {
				close = { "q", mode = "n" },
				send = { "<CR>", mode = "n" },
			},
		}
		open_resolved("first", first)
		mapping("q")()

		open_resolved("second", {
			width = 0.75,
			title = " Hidden Refreshed ",
			on_new_payload = "append",
			close_behavior = "hide",
			wo = { number = true },
			keymaps = { send = { "<F7>", mode = "n" } },
		})

		assert.are.equal(math.floor(vim.o.columns * 0.75), vim.api.nvim_win_get_config(0).width)
		assert.matches("Hidden Refreshed", title())
		assert.matches("%[2/2%]", title())
		assert.is_true(vim.wo[0].number)
		assert.is_function(mapping("<F7>"))
	end)

	it("removes obsolete Wiremux mappings during session refresh", function()
		open_resolved("draft", {
			on_new_payload = "keep",
			keymaps = { send = { "<F5>", mode = "n" } },
		})
		local buf = compose.get_buf()
		assert.is_function(buffer_mapping(buf, "<F5>").callback)

		open_resolved("ignored", {
			on_new_payload = "keep",
			keymaps = { send = { "<F6>", mode = "n" } },
		})

		assert.are.same({}, buffer_mapping(buf, "<F5>"))
		assert.is_function(buffer_mapping(buf, "<F6>").callback)
	end)

	it("preserves a user-replaced mapping instead of reclaiming it", function()
		local compose_config = {
			on_new_payload = "keep",
			keymaps = { send = { "<F5>", mode = "n" } },
		}
		open_resolved("draft", compose_config)
		local buf = compose.get_buf()
		local user_calls = 0
		local user_mapping = function()
			user_calls = user_calls + 1
		end
		vim.keymap.set("n", "<F5>", user_mapping, { buffer = buf })
		local notify = require("wiremux.utils.notify")
		local debug = notify.debug
		local debugged
		notify.debug = function(message)
			debugged = message
		end

		open_resolved("ignored", compose_config)
		notify.debug = debug
		mapping("<F5>")()

		assert.are.equal(1, user_calls)
		assert.matches("preserving", debugged)
	end)

	it("returns to editing after confirmation errors and allows retry", function()
		local calls = 0
		local notify = require("wiremux.utils.notify")
		local notify_error = notify.error
		local error_message
		notify.error = function(message)
			error_message = message
		end
		open("draft", {
			on_confirm = function()
				calls = calls + 1
				if calls == 1 then
					error("prepare failed")
				end
				return false
			end,
		})
		local send = mapping("<CR>")

		send()
		assert.is_true(vim.api.nvim_buf_is_valid(compose.get_buf()))
		send()
		notify.error = notify_error

		assert.are.equal(2, calls)
		assert.matches("prepare failed", error_message)
		assert.is_true(vim.api.nvim_buf_is_valid(compose.get_buf()))
	end)

	it("blocks confirmation re-entry and duplicate confirmation callbacks", function()
		local calls = 0
		local send
		open("draft", {
			on_confirm = function()
				calls = calls + 1
				send()
				return true
			end,
		})
		send = mapping("<CR>")

		send()
		send()

		assert.are.equal(1, calls)
		assert.is_nil(compose.get_buf())
	end)

	it("clears state before a throwing cancellation callback and invokes it once", function()
		local calls = 0
		local state_was_clear = false
		local notify = require("wiremux.utils.notify")
		local notify_error = notify.error
		local error_message
		notify.error = function(message)
			error_message = message
		end
		open_resolved("draft", {
			keymaps = { discard = { "<F8>", mode = "n" } },
		}, {
			on_cancel = function()
				calls = calls + 1
				state_was_clear = compose.get_buf() == nil
				error("cancel failed")
			end,
		})
		local discard = mapping("<F8>")

		discard()
		discard()
		notify.error = notify_error

		assert.are.equal(1, calls)
		assert.is_true(state_was_clear)
		assert.matches("cancel failed", error_message)
	end)

	it("discards only the current page and keeps the others", function()
		local confirmed_pages
		local cancelled = false
		local sources = { { page = 1 }, { page = 2 }, { page = 3 } }
		open("first", { source = sources[1], on_confirm = function() end })
		open("second", { source = sources[2], on_confirm = function() end })
		open("third", {
			source = sources[3],
			on_confirm = function(pages)
				confirmed_pages = pages
				return true
			end,
			on_cancel = function()
				cancelled = true
			end,
		})
		local buf = compose.get_buf()

		mapping("<C-p>")()
		assert.are.equal("second", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		mapping("Q")()

		-- The window stays open on the next page, and the draft loses only page two.
		assert.are.equal(buf, compose.get_buf())
		assert.are.equal("third", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		assert.matches("%[2/2%]", title())
		assert.is_false(cancelled)

		mapping("<CR>")()

		assert.are.equal(2, #confirmed_pages)
		assert.are.equal("first", confirmed_pages[1].text)
		assert.are.equal("third", confirmed_pages[2].text)
		assert.are.equal(sources[1], confirmed_pages[1].source)
		assert.are.equal(sources[3], confirmed_pages[2].source)
	end)

	it("selects the first page when it discards the last page", function()
		open("first", { on_confirm = function() end })
		open("second", { on_confirm = function() end })
		local buf = compose.get_buf()

		mapping("Q")()

		assert.are.equal(buf, compose.get_buf())
		assert.are.equal("first", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
		-- One page remains, so the title drops the page counter.
		assert.are.equal(" Compose Message ", title())
	end)

	it("drops the draft and closes when it discards a one-page draft", function()
		local cancelled = false
		open("only", {
			on_confirm = function()
				error("confirm must not run")
			end,
			on_cancel = function()
				cancelled = true
			end,
		})

		mapping("Q")()

		assert.is_nil(compose.get_buf())
		assert.is_true(cancelled)
	end)

	it("discards without the close prompt", function()
		local confirm_calls = 0
		local vim_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			confirm_calls = confirm_calls + 1
			return 3
		end
		open_resolved("draft", { close_behavior = "ask" }, { on_confirm = function() end })

		mapping("Q")()
		vim.fn.confirm = vim_confirm

		assert.are.equal(0, confirm_calls)
		assert.is_nil(compose.get_buf())
	end)

	it("drops every page when close_behavior discards a multi-page draft", function()
		local cancelled = false
		open_resolved("first", { close_behavior = "discard" }, { on_confirm = function() end })
		open_resolved("second", { close_behavior = "discard" }, {
			on_confirm = function()
				error("confirm must not run")
			end,
			on_cancel = function()
				cancelled = true
			end,
		})

		-- Closing acts on the draft, not on one page, so both pages go.
		mapping("q")()

		assert.is_nil(compose.get_buf())
		assert.is_true(cancelled)
	end)

	it("keeps the draft active after an external window close", function()
		local events = 0
		vim.api.nvim_create_autocmd("User", {
			group = event_group,
			pattern = "WiremuxComposeOpen",
			callback = function()
				events = events + 1
			end,
		})
		open("draft", { on_confirm = function() end })
		local buf = compose.get_buf()
		local old_win = vim.api.nvim_get_current_win()

		vim.api.nvim_win_close(old_win, true)
		assert.are.equal(buf, compose.get_buf())
		compose.open("")

		assert.are.equal(buf, compose.get_buf())
		assert.is_true(vim.api.nvim_win_is_valid(vim.api.nvim_get_current_win()))
		assert.are.equal(2, events)
	end)

	it("ignores delayed file-picker callbacks from a finalized session", function()
		local picker = require("wiremux.picker")
		local files = picker.files
		local picker_callback
		picker.files = function(_, callback)
			picker_callback = callback
		end
		open_resolved("old", {
			keymaps = {
				files = { "<F4>", mode = "n" },
				discard = { "<F8>", mode = "n" },
			},
		})
		mapping("<F4>")()
		picker_callback("stale.txt")
		mapping("<F8>")()
		open("new", { on_confirm = function() end })
		local buf = compose.get_buf()

		vim.wait(20)
		picker.files = files

		assert.are.equal("new", vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1])
	end)

	it("releases the view exactly once during successful finalization", function()
		local compose_view = require("wiremux.ui.compose.view")
		local close = compose_view.close
		local close_calls = 0
		local closed_view
		compose_view.close = function(value)
			close_calls = close_calls + 1
			closed_view = value
			return close(value)
		end
		open("draft", {
			on_confirm = function()
				return true
			end,
		})
		local send = mapping("<CR>")

		send()
		send()
		compose_view.close = close

		assert.are.equal(1, close_calls)
		assert.is_nil(compose_view.get_buf(closed_view))
		assert.is_nil(compose.get_buf())
	end)

	it("releases page sources after successful cleanup", function()
		local source = { marker = "temporary" }
		local weak = setmetatable({ source }, { __mode = "v" })
		open("draft", {
			source = source,
			on_confirm = function()
				return true
			end,
		})
		source = nil

		mapping("<CR>")()
		collectgarbage("collect")
		collectgarbage("collect")

		assert.is_nil(weak[1])
	end)

	it("creates a brand-new empty page with its incoming source", function()
		local source = { marker = "global source" }
		local pages
		open("", {
			source = source,
			on_confirm = function(value)
				pages = value
				return false
			end,
		})

		mapping("<CR>")()

		assert.are.equal(1, #pages)
		assert.are.equal("", pages[1].text)
		assert.are.equal(source, pages[1].source)
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
