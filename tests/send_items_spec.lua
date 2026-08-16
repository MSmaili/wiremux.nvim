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

	it("warns instead of capturing an invalid item value", function()
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
		assert.are.equal("shown", picker_items[1].value.raw_text)
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
			compose_opts.on_confirm({ { text = "edited draft", capture = compose_opts.capture } })
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
			compose_opts.on_confirm({ { text = "edited from opts", capture = compose_opts.capture } })
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

	it("falls back to the action-default compose value", function()
		mocks.config.opts.actions.send.compose = { title = " Action Default " }
		local received_config
		mocks.compose.open = function(_, compose_opts)
			received_config = compose_opts.config
		end

		mocks.send.send("draft")

		assert.are.equal(" Action Default ", received_config.title)
	end)

	it("treats true and an empty table as compose enabled with global defaults", function()
		mocks.config.opts.ui.compose.title = " Global Default "
		local titles = {}
		mocks.compose.open = function(_, compose_opts)
			table.insert(titles, compose_opts.config.title)
		end

		mocks.send.send({ value = "true", compose = true })
		mocks.send.send({ value = "table", compose = {} })

		assert.are.same({ " Global Default ", " Global Default " }, titles)
	end)

	it("uses a compose table and keeps its title separate from the target title", function()
		local compose_config
		local target_title

		mocks.compose.open = function(text, compose_opts)
			compose_config = compose_opts.config
			compose_opts.on_confirm({ { text = text, capture = compose_opts.capture } })
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

	it("captures the global policy only for compose candidates", function()
		mocks.config.opts.ui.compose.capture_placeholders = { "selection", "custom_context" }
		local calls = {}
		mocks.context.capture = function(text, capture_names)
			table.insert(calls, { text = text, capture_names = capture_names })
			return { enabled = true, capture_set = {}, values = {} }
		end

		mocks.send.send("direct {file}")
		mocks.send.send({ value = "compose {file}", compose = true })

		assert.are.equal(2, #calls)
		assert.is_nil(calls[1].capture_names)
		assert.are.same({ "selection", "custom_context" }, calls[2].capture_names)
	end)

	it("transfers one failed eager capture into an explicit page capture", function()
		local placeholder_capture = {
			enabled = true,
			capture_set = { failed = true },
			values = {},
		}
		mocks.context.capture = function()
			return placeholder_capture
		end
		local page_capture
		mocks.compose.open = function(_, compose_opts)
			page_capture = compose_opts.capture
		end

		mocks.send.send({ value = "{failed}", compose = true })

		assert.are.same({ placeholder_capture = placeholder_capture }, page_capture)
		assert.are.equal(placeholder_capture, page_capture.placeholder_capture)
		assert.are.equal(placeholder_capture.capture_set, page_capture.placeholder_capture.capture_set)
		assert.is_true(page_capture.placeholder_capture.capture_set.failed)
		assert.is_nil(page_capture.placeholder_capture.values.failed)
	end)

	it("passes a complete session config without the global capture policy", function()
		mocks.config.opts.ui.compose = {
			width = 0.6,
			height = 0.4,
			title = " Global ",
			wo = { wrap = true, number = false },
			capture_placeholders = { "file" },
		}
		local received_config
		mocks.compose.open = function(_, compose_opts)
			received_config = compose_opts.config
		end

		mocks.send.send({
			value = "draft",
			compose = { title = " Runtime ", wo = { number = true } },
		})

		assert.are.equal(0.6, received_config.width)
		assert.are.equal(0.4, received_config.height)
		assert.are.equal(" Runtime ", received_config.title)
		assert.are.same({ wrap = true, number = true }, received_config.wo)
		assert.is_nil(received_config.capture_placeholders)
	end)

	it("rejects invalid item compose options before capture or UI", function()
		local capture_calls = 0
		local compose_opened = false
		local action_called = false
		local warning
		mocks.context.capture = function()
			capture_calls = capture_calls + 1
		end
		mocks.compose.open = function()
			compose_opened = true
		end
		mocks.action.run = function()
			action_called = true
		end
		mocks.notify.warn = function(message)
			warning = message
		end

		mocks.send.send({ value = "draft", compose = { on_new_payload = "merge" } })

		assert.are.equal(0, capture_calls)
		assert.is_false(compose_opened)
		assert.is_false(action_called)
		assert.matches("invalid on_new_payload", warning)
	end)

	it("rejects capture policy outside global compose config", function()
		local capture_calls = 0
		local compose_opened = false
		local warning
		mocks.context.capture = function()
			capture_calls = capture_calls + 1
		end
		mocks.compose.open = function()
			compose_opened = true
		end
		mocks.notify.warn = function(message)
			warning = message
		end

		mocks.send.send({ value = "draft" }, {
			compose = { capture_placeholders = { "file" } },
		})

		assert.are.equal(0, capture_calls)
		assert.is_false(compose_opened)
		assert.matches("only allowed at ui.compose", warning)
	end)

	it("does not evaluate ignored lower-precedence compose options", function()
		local action_called = false
		mocks.action.run = function()
			action_called = true
		end

		mocks.send.send({ value = "draft", compose = false }, {
			compose = { on_new_payload = "invalid but ignored" },
		})

		assert.is_true(action_called)
	end)

	it("reopens an existing empty compose invocation without recapturing", function()
		mocks.config.opts.ui.compose.capture_placeholders = { "file" }
		mocks.compose.get_buf = function()
			return 10
		end
		mocks.context.capture = function()
			error("capture should not run for an empty reopen")
		end
		local opened = false
		mocks.compose.open = function(text)
			opened = text == ""
		end

		mocks.send.send()

		assert.is_true(opened)
	end)

	it("captures the global policy for a brand-new empty compose draft", function()
		mocks.config.opts.ui.compose.capture_placeholders = { "file", "selection" }
		local captured_text
		local captured_names
		mocks.context.capture = function(text, names)
			captured_text = text
			captured_names = names
			return { enabled = true, capture_set = {}, values = {} }
		end

		mocks.send.send()

		assert.are.equal("", captured_text)
		assert.are.same({ "file", "selection" }, captured_names)
	end)

	it("materializes all compose page captures and preserves empty pages", function()
		local received_text
		local extend_calls = {}
		mocks.context.extend = function(capture, text)
			table.insert(extend_calls, { capture = capture, text = text })
			return capture
		end
		mocks.context.materialize = function(text, capture)
			return text:gsub("{value}", capture.values.value or "{value}")
		end
		mocks.compose.open = function(_, compose_opts)
			local confirmed = compose_opts.on_confirm({
				{
					text = " {value}  ",
					capture = {
						placeholder_capture = {
							enabled = true,
							capture_set = { value = true },
							values = { value = "first" },
						},
					},
				},
				{
					text = "",
					capture = {
						placeholder_capture = { enabled = true, capture_set = {}, values = {} },
					},
				},
				{
					text = "{value}",
					capture = {
						placeholder_capture = {
							enabled = true,
							capture_set = { value = true },
							values = { value = "third" },
						},
					},
				},
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
		assert.are.equal(3, #extend_calls)
		assert.are.same({}, extend_calls[2].capture.values)
	end)

	it("keeps compose open when a page capture is missing", function()
		local confirmation_result
		local action_called = false
		mocks.context.extend = function(capture)
			assert(type(capture) == "table", "missing placeholder capture")
			return capture
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

	it("keeps compose open when a page capture is malformed", function()
		local confirmation_result
		local action_called = false
		mocks.context.extend = function(capture)
			assert(type(capture.capture_set) == "table", "malformed placeholder capture")
			return capture
		end
		mocks.compose.open = function(_, compose_opts)
			confirmation_result = compose_opts.on_confirm({
				{ text = "draft", capture = { placeholder_capture = { enabled = true } } },
			})
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

	it("warns and omits invalid runtime candidates before the picker", function()
		local picker_items
		local capture_calls = 0
		local warnings = {}
		mocks.context.capture = function()
			capture_calls = capture_calls + 1
			return { enabled = true, capture_set = {}, values = {} }
		end
		mocks.notify.warn = function(message)
			table.insert(warnings, message)
		end
		mocks.picker.select = function(items)
			picker_items = items
		end

		mocks.send.send({
			{ value = "invalid", compose = { close_behavior = "explode" } },
			{ value = "valid", compose = true },
			{ label = "missing value" },
		})

		assert.are.equal(1, #picker_items)
		assert.are.equal("valid", picker_items[1].value.raw_text)
		assert.are.equal(1, capture_calls)
		assert.are.equal(2, #warnings)
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

	it("captures independent placeholder state for each picker item", function()
		local captured = {}
		local selected_capture
		mocks.context.capture = function(text)
			captured[text] = { enabled = true, capture_set = { source = true }, values = { source = text } }
			return captured[text]
		end
		mocks.context.extend = function(capture)
			selected_capture = capture
			return capture
		end
		mocks.context.materialize = function()
			return "expanded"
		end
		mocks.picker.select = function(items, _, callback)
			callback(items[2])
		end

		mocks.send.send({
			{ value = "first {one}" },
			{ value = "second {two}" },
		})

		assert.are.equal(captured["second {two}"], selected_capture)
		assert.are_not.equal(captured["first {one}"], selected_capture)
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
