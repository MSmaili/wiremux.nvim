---@module 'luassert'

local helpers = require("tests.helpers_send")

describe("send single item", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("handles SendItem table", function()
		local run_called = false

		mocks.action.run = function(opts, callbacks)
			run_called = true
		end

		mocks.send.send({
			value = "npm test",
			label = "Run tests",
		})

		assert.is_true(run_called)
	end)

	it("warns instead of snapshotting an invalid item value", function()
		local warning
		mocks.notify.warn = function(message)
			warning = message
		end

		local ok = pcall(mocks.send.send, { label = "Missing value" })

		assert.is_true(ok)
		assert.matches("item.value must be a string", warning)
	end)

	it("uses visible field to filter items", function()
		local picker_items = {}

		mocks.picker.select = function(items, opts, callback)
			picker_items = items
		end

		mocks.action.run = function()
			return { kind = "pick", items = {} }
		end

		mocks.send.send({
			{
				value = "visible item",
				visible = true,
			},
			{
				value = "hidden item",
				visible = false,
			},
			{
				value = "default visible",
			},
		})

		assert.are.equal(2, #picker_items)
	end)

	it("calls visible function and filters based on return value", function()
		local picker_items = {}
		local fn_called = false

		mocks.picker.select = function(items, opts, callback)
			picker_items = items
		end

		-- Test visible returns true
		mocks.send.send({
			{
				value = "shown",
				visible = function()
					fn_called = true
					return true
				end,
			},
			{
				value = "hidden",
				visible = function()
					return false
				end,
			},
		})

		assert.is_true(fn_called)
		assert.are.equal(1, #picker_items)
		assert.are.equal("shown", picker_items[1].value.value)
	end)

	it("uses submit option from item", function()
		local send_opts

		mocks.backend.send = function(text, targets, opts, state)
			send_opts = opts
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send({
			value = "go test ./...",
			submit = true,
		})

		assert.is_nil(send_opts.submit)
		assert.are.same({ "Enter" }, send_opts.post_keys)
	end)

	it("falls back to config submit option", function()
		local send_opts

		mocks.backend.send = function(text, targets, opts, state)
			send_opts = opts
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.config.opts.actions.send.submit = true
		mocks.send.send({ value = "npm test" })

		assert.is_nil(send_opts.submit)
		assert.are.same({ "Enter" }, send_opts.post_keys)
	end)

	it("opens compose buffer when item.compose is true", function()
		local received_text
		local compose_opened = false

		mocks.compose.open = function(text, compose_opts)
			compose_opened = true
			assert.are.equal("draft", text)
			compose_opts.on_confirm({ { text = "edited draft", meta = compose_opts.page_meta } })
		end

		mocks.backend.send = function(text)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return received_text ~= nil
		end)

		assert.is_true(compose_opened)
		assert.are.equal("edited draft", received_text)
	end)

	it("uses opts.compose when item has no compose field", function()
		local received_text
		local compose_opened = false

		mocks.compose.open = function(text, compose_opts)
			compose_opened = true
			assert.are.equal("draft", text)
			compose_opts.on_confirm({ { text = "edited from opts", meta = compose_opts.page_meta } })
		end

		mocks.backend.send = function(text)
			received_text = text
		end

		mocks.action.run = function(opts, callbacks)
			callbacks.on_targets({
				{ id = "%1", kind = "pane", target = "test" },
			}, {})
		end

		mocks.send.send({ value = "draft" }, { compose = true })
		vim.wait(100, function()
			return received_text ~= nil
		end)

		assert.is_true(compose_opened)
		assert.are.equal("edited from opts", received_text)
	end)

	it("uses a compose table and keeps its title separate from the target title", function()
		local compose_config
		local target_title

		mocks.compose.open = function(text, compose_opts)
			compose_config = compose_opts.compose
			compose_opts.on_confirm({ { text = text, meta = compose_opts.page_meta } })
		end
		mocks.action.run = function(_, callbacks)
			callbacks.on_definition("test", {}, {})
		end
		mocks.backend.create = function(_, def)
			target_title = def.title
		end

		mocks.send.send({
			value = "draft",
			compose = {
				title = " Review ",
				close_behavior = "hide",
				on_new_payload = "append",
			},
			title = "target",
		})
		vim.wait(100, function()
			return target_title ~= nil
		end)

		assert.are.same({
			title = " Review ",
			close_behavior = "hide",
			on_new_payload = "append",
		}, compose_config)
		assert.are.equal("target", target_title)
	end)

	it("uses whole-value compose precedence", function()
		local compose_opened = false
		local action_called = false
		mocks.compose.open = function()
			compose_opened = true
		end
		mocks.action.run = function()
			action_called = true
		end

		mocks.send.send({ value = "draft", compose = false }, { compose = { title = "Ignored" } })

		assert.is_false(compose_opened)
		assert.is_true(action_called)
	end)

	it("prepares all compose pages with strict snapshots and preserves empty pages", function()
		local received_text
		local expand_calls = {}
		mocks.context.expand = function(text, snapshot, opts)
			table.insert(expand_calls, { snapshot = snapshot, opts = opts })
			return text:gsub("{value}", snapshot.value or "{value}")
		end
		mocks.compose.open = function(_, compose_opts)
			local confirmed = compose_opts.on_confirm({
				{ text = " {value}  ", meta = { snapshot = { value = "first" } } },
				{ text = "", meta = nil },
				{ text = "{value}", meta = { snapshot = { value = "third" } } },
			})
			assert.is_true(confirmed)
		end
		mocks.backend.send = function(text)
			received_text = text
		end
		mocks.action.run = function(_, callbacks)
			callbacks.on_targets({}, {})
		end

		mocks.send.send({ value = "draft", compose = true })
		vim.wait(100, function()
			return received_text ~= nil
		end)

		assert.are.equal(" first\n\n\n\nthird", received_text)
		assert.are.equal(3, #expand_calls)
		assert.is_false(expand_calls[1].opts.resolve_missing)
		assert.are.same({}, expand_calls[2].snapshot)
	end)

	it("keeps compose open when a page cannot be prepared", function()
		local confirmation_result
		local action_called = false
		mocks.context.expand = function()
			error("broken snapshot")
		end
		mocks.compose.open = function(_, compose_opts)
			confirmation_result = compose_opts.on_confirm({ { text = "draft" } })
		end
		mocks.action.run = function()
			action_called = true
		end

		mocks.send.send({ value = "draft", compose = true })

		assert.is_false(confirmation_result)
		assert.is_false(action_called)
	end)
end)

describe("send list of items", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	it("shows picker when sending array of items", function()
		local picker_shown = false

		mocks.picker.select = function(items, opts, callback)
			picker_shown = true
			assert.are.equal(3, #items)
		end

		mocks.send.send({
			{ value = "test1" },
			{ value = "test2" },
			{ value = "test3" },
		})

		assert.is_true(picker_shown)
	end)

	it("uses label or value for display", function()
		local picker_items = {}

		mocks.picker.select = function(items, opts, callback)
			picker_items = items
		end

		mocks.send.send({
			{ value = "cmd1", label = "Custom Label" },
			{ value = "cmd2" },
		})

		assert.are.equal("Custom Label", picker_items[1].label)
		assert.are.equal("cmd2", picker_items[2].label)
	end)

	it("sends selected item to target", function()
		local send_called = false
		local received_text

		mocks.backend.send = function(text, targets, opts, state)
			send_called = true
			received_text = text
		end

		mocks.picker.select = function(items, opts, callback)
			callback(items[2])
		end

		mocks.send.send({
			{ value = "first" },
			{ value = "selected" },
		})

		assert.is_true(send_called)
		assert.are.equal("selected", received_text)
	end)

	it("captures an independent context snapshot for each picker item", function()
		local captured = {}
		local selected_snapshot
		mocks.context.snapshot = function(text)
			captured[text] = { source = text }
			return captured[text]
		end
		mocks.context.expand = function(_, snapshot)
			selected_snapshot = snapshot
			return "expanded"
		end
		mocks.picker.select = function(items, _, callback)
			callback(items[2])
		end

		mocks.send.send({
			{ value = "first {one}" },
			{ value = "second {two}" },
		})

		assert.are.equal(captured["second {two}"], selected_snapshot)
		assert.are_not.equal(captured["first {one}"], selected_snapshot)
	end)

	it("handles picker cancellation", function()
		local send_called = false

		mocks.backend.send = function()
			send_called = true
		end

		mocks.picker.select = function(items, opts, callback)
			callback(nil)
		end

		mocks.send.send({
			{ value = "item1" },
			{ value = "item2" },
		})

		assert.is_false(send_called)
	end)

	it("warns when all items are hidden", function()
		local warned = false
		local warning_msg

		mocks.notify.warn = function(msg)
			warned = true
			warning_msg = msg
		end

		mocks.send.send({
			{ value = "hidden1", visible = false },
			{ value = "hidden2", visible = false },
		})

		assert.is_true(warned)
		assert.matches("No items", warning_msg)
	end)
end)
