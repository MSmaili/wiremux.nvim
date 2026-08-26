---@module 'luassert'

local helpers = require("tests.helpers")

local MODULES = {
	"wiremux.action.send",
	"wiremux.action.send.delivery",
	"wiremux.action.send.request",
	"wiremux.backend",
	"wiremux.config",
	"wiremux.context",
	"wiremux.core.action",
	"wiremux.core.resolver",
	"wiremux.picker",
	"wiremux.ui.compose",
	"wiremux.ui.compose.draft",
	"wiremux.ui.compose.view",
	"wiremux.utils.notify",
}

describe("send compose integration", function()
	local compose
	local config
	local context
	local deliveries
	local delivery_boundary
	local send
	local test_buffers

	local function setup(options)
		options = options or {}
		options.log_level = "off"
		config = require("wiremux.config")
		config.setup(options)
		context = require("wiremux.context")
		compose = require("wiremux.ui.compose")
		send = require("wiremux.action.send")
	end

	local function new_source(name, lines)
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, name)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "source" })
		vim.api.nvim_set_current_buf(buf)
		table.insert(test_buffers, buf)
		return buf
	end

	local function mapping(key)
		return vim.fn.maparg(key, "n", false, true).callback
	end

	local function set_compose_text(text)
		vim.api.nvim_buf_set_lines(compose.get_buf(), 0, -1, false, vim.split(text, "\n"))
	end

	local function window_title()
		local value = vim.api.nvim_win_get_config(0).title
		return type(value) == "table" and value[1][1] or value
	end

	local function confirm()
		mapping("<CR>")()
	end

	local function hide()
		mapping("q")()
	end

	local function wait_for_deliveries(count)
		vim.wait(100, function()
			return #deliveries >= count
		end)
	end

	before_each(function()
		helpers.clear(MODULES)
		deliveries = {}
		test_buffers = {}
		delivery_boundary = {
			send = function(payload, options, target_title)
				table.insert(deliveries, {
					payload = payload,
					options = vim.deepcopy(options),
					target_title = target_title,
				})
				return true, nil
			end,
		}
		helpers.register({ ["wiremux.action.send.delivery"] = delivery_boundary })
	end)

	after_each(function()
		if compose then
			local compose_buf = compose.get_buf()
			if compose_buf and vim.api.nvim_buf_is_valid(compose_buf) then
				vim.api.nvim_buf_delete(compose_buf, { force = true })
			end
		end
		for _, buf in ipairs(test_buffers) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.fn.setqflist({}, "r")
		if context then
			context.configure()
		end
		helpers.clear(MODULES)
	end)

	it("resolves each page against its own origin and uses the latest delivery options", function()
		local resolver_calls = 0
		setup({
			context = {
				resolvers = {
					page_state = function(origin)
						resolver_calls = resolver_calls + 1
						return origin and origin.line or vim.api.nvim_get_current_line()
					end,
				},
			},
			ui = {
				compose = {
					on_new_payload = "append",
					close_behavior = "hide",
				},
			},
		})
		local source = new_source("/tmp/wiremux-page-state.lua", { "state one" })

		send.send("{page_state}", {
			compose = true,
			focus = false,
			pre_keys = { "first" },
		})
		hide()
		vim.api.nvim_set_current_buf(source)
		vim.api.nvim_buf_set_lines(source, 0, -1, false, { "state two" })
		send.send("{page_state}", {
			compose = true,
			focus = true,
			pre_keys = { "second" },
			post_keys = { "latest" },
		})

		-- Nothing resolves until the draft is confirmed.
		assert.are.equal(0, resolver_calls)
		confirm()
		wait_for_deliveries(1)

		assert.are.equal(2, resolver_calls)
		assert.are.equal("state one\n\nstate two", deliveries[1].payload)
		assert.is_true(deliveries[1].options.focus)
		assert.are.same({ "second" }, deliveries[1].options.pre_keys)
		assert.are.same({ "latest" }, deliveries[1].options.post_keys)
	end)

	it("resolves a zero-argument resolver at confirmation time", function()
		local live_value = "before"
		setup({
			context = {
				resolvers = {
					live_state = function()
						return live_value
					end,
				},
			},
			ui = { compose = { close_behavior = "hide" } },
		})
		new_source("/tmp/wiremux-live-state.lua", { "source" })

		send.send("{live_state}", { compose = true })
		live_value = "after"

		confirm()
		wait_for_deliveries(1)

		-- A resolver that ignores the origin is not frozen; it resolves when the draft is sent.
		assert.are.equal("after", deliveries[1].payload)
	end)

	it("resolves names typed later against each page source origin", function()
		setup({
			ui = {
				compose = {
					on_new_payload = "append",
					close_behavior = "hide",
				},
			},
		})
		new_source("/tmp/wiremux-origin-one.lua", { "source one" })
		send.send("page one", { compose = true })
		set_compose_text("page one {line}")
		hide()

		new_source("/tmp/wiremux-origin-two.lua", { "source two" })
		send.send("page two", { compose = true })
		set_compose_text("page two {line}")
		confirm()
		wait_for_deliveries(1)

		assert.are.equal("page one source one\n\npage two source two", deliveries[1].payload)
	end)

	it("resolves initial and later-typed names once each, leaving the page text unchanged", function()
		local calls = { initial = 0, live = 0 }
		setup({
			context = {
				resolvers = {
					initial_value = function()
						calls.initial = calls.initial + 1
						return "page snapshot"
					end,
					live_later = function()
						calls.live = calls.live + 1
						return "confirmation value"
					end,
				},
			},
			ui = { compose = { close_behavior = "hide" } },
		})
		new_source("/tmp/wiremux-working-source.lua", { "source" })
		send.send("{initial_value}", { compose = true })

		-- Preparing the draft resolves nothing.
		assert.are.same({ initial = 0, live = 0 }, calls)
		set_compose_text("{initial_value}|{live_later}")
		local text_before = table.concat(vim.api.nvim_buf_get_lines(compose.get_buf(), 0, -1, false), "\n")

		confirm()
		wait_for_deliveries(1)

		assert.are.equal("page snapshot|confirmation value", deliveries[1].payload)
		assert.are.same({ initial = 1, live = 1 }, calls)
		assert.are.equal("{initial_value}|{live_later}", text_before)
	end)

	it("resolves buffers and quickfix from confirmation-time editor state", function()
		setup()
		local source = new_source("/tmp/wiremux-live-builtins.lua", { "source" })
		send.send("raw", { compose = true })
		vim.fn.setqflist({}, "r", {
			title = "Integration",
			items = { {
				bufnr = source,
				lnum = 1,
				col = 1,
				text = "integration issue",
			} },
		})
		set_compose_text("{buffers}\n{quickfix}")

		confirm()
		wait_for_deliveries(1)

		assert.matches("/tmp/wiremux%-live%-builtins.lua", deliveries[1].payload)
		assert.matches("Quickfix: Integration", deliveries[1].payload)
		assert.matches("integration issue", deliveries[1].payload)
	end)

	it("preserves the accepted empty, unknown, error, nil, and invalid outcomes", function()
		local calls = { empty = 0, errored = 0, missing = 0, invalid = 0 }
		setup({
			context = {
				resolvers = {
					empty_result = function()
						calls.empty = calls.empty + 1
						return ""
					end,
					error_result = function()
						calls.errored = calls.errored + 1
						error("failed")
					end,
					nil_result = function()
						calls.missing = calls.missing + 1
						return nil
					end,
					invalid_result = function()
						calls.invalid = calls.invalid + 1
						return false
					end,
				},
			},
		})
		local raw = table.concat({
			"{unknown_result}",
			"{error_result}",
			"{nil_result}",
			"{invalid_result}",
			"{empty_result}",
		}, "|")

		send.send(raw, { compose = true })
		confirm()
		wait_for_deliveries(1)

		assert.are.equal("{unknown_result}|{error_result}|{nil_result}|{invalid_result}|", deliveries[1].payload)
		assert.are.same({ empty = 1, errored = 1, missing = 1, invalid = 1 }, calls)
	end)

	it("resolves no library candidate before selection and only the chosen one after", function()
		local resolver_calls = 0
		local picker_items
		local picker_callback
		setup({
			context = {
				resolvers = {
					candidate_value = function()
						resolver_calls = resolver_calls + 1
						return "candidate " .. resolver_calls
					end,
				},
			},
			picker = {
				adapter = function(items, _, callback)
					picker_items = items
					picker_callback = callback
				end,
			},
		})
		new_source("/tmp/wiremux-library-source.lua", { "source" })

		send.send({
			{ label = "first", value = "{candidate_value}", compose = true },
			{ label = "second", value = "{candidate_value}", compose = true },
		})

		assert.are.equal(0, resolver_calls)
		assert.is_nil(compose.get_buf())
		assert.are_not.equal(picker_items[1].value.source, picker_items[2].value.source)
		assert.are.equal(picker_items[1].value.source.origin, picker_items[2].value.source.origin)

		picker_callback(picker_items[2])
		confirm()
		wait_for_deliveries(1)

		assert.are.equal("candidate 1", deliveries[1].payload)
		assert.are.equal(1, resolver_calls)
	end)

	it("preserves the full draft and sends nothing when one page source is malformed", function()
		setup({
			context = { resolvers = {
				page_value = function()
					return "value"
				end,
			} },
			ui = {
				compose = {
					on_new_payload = "append",
					close_behavior = "hide",
				},
			},
		})
		local draft_model = require("wiremux.ui.compose.draft")
		local append = draft_model.append
		draft_model.append = function(draft, text, source)
			append(draft, text, source)
			draft.pages[#draft.pages].source = nil
		end

		send.send("first {page_value}", { compose = true })
		hide()
		send.send("second {page_value}", { compose = true })

		confirm()
		draft_model.append = append

		assert.are.equal(0, #deliveries)
		assert.is_true(vim.api.nvim_buf_is_valid(compose.get_buf()))
		assert.matches("%[2/2%]", window_title())
	end)

	it("releases page sources across replace, discard, and external wipeout", function()
		setup({
			context = { resolvers = {
				release_value = function()
					return "resolved"
				end,
			} },
			ui = {
				compose = {
					on_new_payload = "replace",
					close_behavior = "discard",
				},
			},
		})
		local draft_model = require("wiremux.ui.compose.draft")
		local sources = setmetatable({}, { __mode = "v" })
		local count = 0
		local new, replace = draft_model.new, draft_model.replace
		draft_model.new = function(text, source)
			count = count + 1
			sources[count] = source
			return new(text, source)
		end
		draft_model.replace = function(draft, text, source)
			count = count + 1
			sources[count] = source
			return replace(draft, text, source)
		end

		send.send("{release_value}", { compose = true })
		send.send("{release_value}", { compose = true })
		collectgarbage("collect")
		collectgarbage("collect")
		assert.is_nil(sources[1])
		assert.is_not_nil(sources[2])

		mapping("q")()
		collectgarbage("collect")
		collectgarbage("collect")
		assert.is_nil(sources[2])

		send.send("{release_value}", { compose = true })
		vim.api.nvim_buf_delete(compose.get_buf(), { force = true })
		collectgarbage("collect")
		collectgarbage("collect")
		draft_model.new, draft_model.replace = new, replace

		assert.is_nil(sources[3])
		assert.is_nil(compose.get_buf())
	end)

	it("keeps the confirmed draft cleared when the real target picker is cancelled", function()
		package.loaded["wiremux.action.send"] = nil
		package.loaded["wiremux.action.send.delivery"] = nil
		local target_picker_called = false
		local backend_calls = 0
		local backend = helpers.mock_backend({
			state = {
				get = function()
					return { instances = {}, last_used_target_id = nil }
				end,
			},
			send = function()
				backend_calls = backend_calls + 1
			end,
			create = function()
				backend_calls = backend_calls + 1
			end,
		})
		helpers.register({
			["wiremux.backend"] = {
				get = function()
					return backend
				end,
			},
		})
		setup({
			targets = { definitions = { first = {}, second = {} } },
			picker = {
				adapter = function(_, options, callback)
					assert.are.equal("Send to", options.prompt)
					target_picker_called = true
					callback(nil)
				end,
			},
		})

		send.send("confirmed", {
			compose = true,
			behavior = "pick",
			mode = "definitions",
		})
		confirm()
		assert.is_nil(compose.get_buf())
		vim.wait(100, function()
			return target_picker_called
		end)

		assert.is_true(target_picker_called)
		assert.are.equal(0, backend_calls)
	end)
end)
