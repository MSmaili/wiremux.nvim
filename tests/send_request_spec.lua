---@module 'luassert'

local helpers = require("tests.helpers_send")

describe("prepared send request", function()
	local mocks
	local request_builder

	before_each(function()
		mocks = helpers.setup()
		request_builder = require("wiremux.action.send.request")
	end)

	after_each(function()
		helpers.teardown()
	end)

	local function prepare_context(opts)
		local preparation, errors = request_builder.prepare_context(opts, mocks.config.get())
		assert.are.same({}, errors)
		assert.is_not_nil(preparation)
		return preparation
	end

	it("resolves delivery and item option precedence into explicit fields", function()
		local default_filter = {
			instances = function()
				return false
			end,
		}
		local call_filter_fn = function()
			return true
		end
		mocks.config.opts.actions.send = {
			focus = false,
			behavior = "pick",
			mode = "instances",
			target = "default-target",
			filter = default_filter,
			submit = false,
			pre_keys = { "default-pre" },
			post_keys = { "default-post" },
			compose = { title = " Default Compose " },
		}
		mocks.config.opts.ui.compose.width = 0.6

		local preparation = prepare_context({
			focus = true,
			behavior = "last",
			mode = "definitions",
			target = "call-target",
			filter = { instances = call_filter_fn },
			submit = false,
			pre_keys = { "call-pre" },
			post_keys = { "call-post" },
			compose = { title = " Call Compose " },
		})
		local request, errors = request_builder.prepare({
			value = "payload",
			label = "Label",
			title = "Target Title",
			submit = true,
			pre_keys = { "item-pre" },
			post_keys = { "item-post" },
			compose = { title = " Item Compose " },
		}, preparation)

		assert.are.same({}, errors)
		assert.are.equal("payload", request.raw_text)
		assert.are.equal("Label", request.label)
		assert.are.equal("Target Title", request.target_title)
		assert.is_true(request.delivery.focus)
		assert.are.equal("last", request.delivery.behavior)
		assert.are.equal("definitions", request.delivery.mode)
		assert.are.equal("call-target", request.delivery.target)
		assert.are.equal(call_filter_fn, request.delivery.filter.instances)
		assert.are.same({ "item-pre" }, request.delivery.pre_keys)
		assert.are.same({ "item-post", "Enter" }, request.delivery.post_keys)
		assert.are.equal(" Item Compose ", request.compose.title)
		assert.are.equal(0.6, request.compose.width)
		assert.is_true(request.source.resolve)
		assert.are.same(
			{ bufnr = 1, path = "/source.lua", row = 1, col = 0, selection = "", line = "" },
			request.source.origin
		)
	end)

	it("marks the source literal when placeholders are disabled", function()
		local request = assert(request_builder.prepare({
			value = "literal {file}",
			compose = true,
			placeholders = false,
		}, prepare_context()))

		assert.is_false(request.source.resolve)
		assert.are.same(
			{ bufnr = 1, path = "/source.lua", row = 1, col = 0, selection = "", line = "" },
			request.source.origin
		)
	end)

	it("uses call then action defaults when item-specific fields are absent", function()
		mocks.config.opts.actions.send = {
			focus = true,
			behavior = "all",
			mode = "instances",
			target = "default-target",
			submit = true,
			pre_keys = { "default-pre" },
			post_keys = { "default-post" },
			compose = { title = " Default Compose " },
		}
		local preparation = prepare_context({
			submit = false,
			pre_keys = { "call-pre" },
			compose = { title = " Call Compose " },
		})

		local request = assert(request_builder.prepare({ value = "payload" }, preparation))

		assert.is_true(request.delivery.focus)
		assert.are.equal("all", request.delivery.behavior)
		assert.are.equal("instances", request.delivery.mode)
		assert.are.equal("default-target", request.delivery.target)
		assert.are.same({ "call-pre" }, request.delivery.pre_keys)
		assert.are.same({ "default-post" }, request.delivery.post_keys)
		assert.are.equal(" Call Compose ", request.compose.title)
	end)

	it("applies compose whole-value precedence exactly once", function()
		mocks.config.opts.actions.send.compose = { title = " Default " }
		local compose_config = require("wiremux.ui.compose.config")
		local resolve_compose = compose_config.resolve
		local calls = 0
		compose_config.resolve = function(...)
			calls = calls + 1
			return resolve_compose(...)
		end

		local preparation = prepare_context({ compose = { title = " Call " } })
		local request = assert(request_builder.prepare({
			value = "payload",
			compose = { title = " Item " },
		}, preparation))
		compose_config.resolve = resolve_compose

		assert.are.equal(1, calls)
		assert.are.equal(" Item ", request.compose.title)
	end)

	it("lets an item override a true call option with false", function()
		local preparation = prepare_context({ submit = true, post_keys = { "Escape" } })
		local request = assert(request_builder.prepare({ value = "payload", submit = false }, preparation))

		assert.are.same({ "Escape" }, request.delivery.post_keys)
	end)

	it("folds submit into a copied post-keys list", function()
		local post_keys = { "Escape" }
		local preparation = prepare_context({ post_keys = post_keys, submit = true })
		local request = assert(request_builder.prepare({ value = "payload" }, preparation))

		assert.are.same({ "Escape" }, post_keys)
		assert.are.same({ "Escape", "Enter" }, request.delivery.post_keys)
		assert.are_not.equal(post_keys, request.delivery.post_keys)
	end)

	it("reports invalid inputs before any resolution", function()
		local resolves = 0
		mocks.context.resolve = function(text)
			resolves = resolves + 1
			return text
		end
		local request, errors = request_builder.prepare({
			value = "draft",
			placeholders = "no",
		}, prepare_context())

		assert.is_nil(request)
		assert.are.equal(0, resolves)
		assert.are.equal("item.placeholders", errors[1].path)
		assert.matches("item.placeholders must be a boolean", errors[1].message)
	end)

	it("treats item, option, and config input as read-only", function()
		local item_pre = { "item-pre" }
		mocks.config.opts.ui.compose.wo = { wrap = true }
		local item = {
			value = "original",
			title = "Original Title",
			pre_keys = item_pre,
			compose = true,
		}
		local option_post = { "option-post" }
		local option_filter = {
			instances = function()
				return true
			end,
		}
		local opts = {
			behavior = "last",
			filter = option_filter,
			post_keys = option_post,
		}
		local config_before = vim.deepcopy(mocks.config.opts)

		local preparation = prepare_context(opts)
		local request = assert(request_builder.prepare(item, preparation))

		item.value = "mutated"
		item.title = "Mutated Title"

		assert.are.equal("original", request.raw_text)
		assert.are.equal("Original Title", request.target_title)
		assert.are.equal(item_pre, request.delivery.pre_keys)
		assert.are.equal(option_post, request.delivery.post_keys)
		assert.are.equal("last", request.delivery.behavior)
		assert.are.equal(option_filter, request.delivery.filter)
		assert.is_false(request.delivery.focus)
		assert.is_true(request.compose.wo.wrap)
		assert.are.same(config_before, mocks.config.opts)
	end)
end)

describe("prepared request orchestration", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	after_each(function()
		helpers.teardown()
	end)

	it("bypasses resolution and preserves literal placeholder-shaped text", function()
		mocks.context.resolve = function()
			error("literal payload must bypass resolution")
		end
		local received
		mocks.backend.send = function(text)
			received = text
		end
		mocks.action.run = function(_, callbacks)
			callbacks.on_targets({}, {})
		end

		mocks.send.send({ value = "local value = '{file}'", placeholders = false })

		assert.are.equal("local value = '{file}'", received)
	end)

	it("prepares independent picker requests without resolving before selection", function()
		local resolves = 0
		local picker_items
		local choose
		mocks.context.resolve = function(text)
			resolves = resolves + 1
			return text
		end
		mocks.picker.select = function(items, _, callback)
			picker_items = items
			choose = callback
		end

		mocks.send.send({ { value = "first" }, { value = "second" } })

		assert.are.equal(0, resolves)
		assert.are_not.equal(picker_items[1].value.source, picker_items[2].value.source)
		assert.are.equal(picker_items[1].value.source.origin, picker_items[2].value.source.origin)
		assert.is_not_nil(choose)
	end)

	it("resolves only the selected request, once, without reading config again", function()
		local picker_items
		local choose
		local resolved = {}
		mocks.context.resolve = function(text)
			table.insert(resolved, text)
			return text
		end
		mocks.picker.select = function(items, _, callback)
			picker_items = items
			choose = callback
		end
		local received
		mocks.backend.send = function(text)
			received = text
		end
		mocks.action.run = function(_, callbacks)
			callbacks.on_targets({}, {})
		end

		mocks.send.send({ { value = "first" }, { value = "selected" } })
		assert.are.equal(0, #resolved)

		mocks.config.get = function()
			error("config must not be read after preparation")
		end
		choose(picker_items[2])

		assert.are.same({ "selected" }, resolved)
		assert.are.equal("selected", received)
	end)

	it("rejects invalid runtime compose before resolution or UI", function()
		local resolves = 0
		local opened = false
		local warning
		mocks.context.resolve = function(text)
			resolves = resolves + 1
			return text
		end
		mocks.compose.open = function()
			opened = true
		end
		mocks.notify.warn = function(message)
			warning = message
		end

		mocks.send.send({ value = "draft", compose = { close_behavior = "explode" } })

		assert.are.equal(0, resolves)
		assert.is_false(opened)
		assert.matches("invalid close_behavior", warning)
	end)

	it("reopens a live empty invocation without reading config or resolving", function()
		mocks.compose.get_buf = function()
			return 10
		end
		mocks.config.get = function()
			error("empty reopen must not read new config")
		end
		mocks.context.resolve = function()
			error("empty reopen must not resolve")
		end
		local open_text
		mocks.compose.open = function(text)
			open_text = text
		end

		mocks.send.send("")

		assert.are.equal("", open_text)
	end)
end)

describe("send motion request", function()
	it("always sends selected source in literal-payload mode", function()
		local original_wiremux = package.loaded["wiremux"]
		local original_buf = vim.api.nvim_get_current_buf()
		local buf = vim.api.nvim_create_buf(false, true)
		local received_item
		local received_opts
		package.loaded["wiremux"] = {
			send = function(item, opts)
				received_item = item
				received_opts = opts
			end,
		}
		package.loaded["wiremux.action.send_motion"] = nil
		local send_motion = require("wiremux.action.send_motion")
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local value = '{file}'" })
		vim.api.nvim_buf_set_mark(buf, "[", 1, 0, {})
		vim.api.nvim_buf_set_mark(buf, "]", 1, 21, {})
		local opts = { target = "terminal" }

		send_motion.send_motion(opts)
		send_motion.operator("char")

		vim.api.nvim_set_current_buf(original_buf)
		vim.api.nvim_buf_delete(buf, { force = true })
		package.loaded["wiremux"] = original_wiremux
		package.loaded["wiremux.action.send_motion"] = nil
		assert.are.same({ value = "local value = '{file}'", placeholders = false }, received_item)
		assert.are.equal(opts, received_opts)
	end)
end)
