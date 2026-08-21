---@module 'luassert'

describe("compose configuration", function()
	it("accepts append and rejects unknown payload policies", function()
		local validate = require("wiremux.utils.validate")
		local _, valid_errors = validate.compose_options({ on_new_payload = "append" })
		local _, invalid_errors = validate.compose_options({ on_new_payload = "merge" })

		assert.are.same({}, valid_errors)
		assert.are.equal(1, #invalid_errors)
		assert.matches("invalid on_new_payload", invalid_errors[1].message)
	end)

	it("provides previous and next navigation defaults", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup()

		assert.are.equal("<C-p>", config.opts.ui.compose.keymaps.previous[1])
		assert.are.equal("<C-n>", config.opts.ui.compose.keymaps.next[1])
	end)

	it("replaces custom resolvers on repeated setup", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		local context = require("wiremux.context")

		config.setup({
			log_level = "off",
			context = { resolvers = { first = function()
				return "first"
			end } },
		})
		assert.are.equal("first", context.get("first"))

		config.setup({
			log_level = "off",
			context = { resolvers = { second = function()
				return "second"
			end } },
		})
		assert.is_nil(context.get("first"))
		assert.are.equal("second", context.get("second"))
		assert.is_not_nil(context.get("position"))

		config.setup()
	end)

	it("validates resolver names with the placeholder grammar", function()
		local validate = require("wiremux.utils.validate")
		local errors = validate.validate({
			context = { resolvers = { ["bad-name"] = function()
				return "invalid"
			end } },
		})

		assert.are.equal(1, #errors)
		assert.matches("resolver name", errors[1])
	end)

	it("provides the lightweight capture policy without opt-in defaults", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup({ log_level = "off" })

		assert.are.same({
			"file",
			"filename",
			"position",
			"line",
			"selection",
			"this",
		}, config.opts.ui.compose.capture_placeholders)
		for _, name in ipairs({ "buffers", "quickfix", "diagnostics", "diagnostics_all", "changes" }) do
			assert.is_false(vim.tbl_contains(config.opts.ui.compose.capture_placeholders, name))
		end
	end)

	it("preserves an explicit empty global capture policy", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup({
			log_level = "off",
			ui = { compose = { capture_placeholders = {} } },
		})

		assert.are.same({}, config.opts.ui.compose.capture_placeholders)
	end)

	it("accepts configured resolvers in the capture policy and omits unknown names", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup({
			log_level = "off",
			context = { resolvers = { custom_context = function()
				return "custom"
			end } },
			ui = {
				compose = {
					capture_placeholders = { "custom_context", "unknown_context", "bad-name" },
				},
			},
		})

		assert.are.same({ "custom_context" }, config.opts.ui.compose.capture_placeholders)
	end)

	it("falls back from malformed global compose values even when logging is off", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup({
			log_level = "off",
			ui = {
				compose = {
					width = "wide",
					close_behavior = "explode",
					capture_placeholders = "file",
					keymaps = { send = { "<C-x>", mode = "invalid" } },
				},
			},
		})

		assert.are.equal(0.6, config.opts.ui.compose.width)
		assert.are.equal("ask", config.opts.ui.compose.close_behavior)
		assert.are.same({
			"file",
			"filename",
			"position",
			"line",
			"selection",
			"this",
		}, config.opts.ui.compose.capture_placeholders)
		assert.are.equal("<C-s>", config.opts.ui.compose.keymaps.send[1][1])
	end)

	it("normalizes action-default compose tables without capture-policy fields", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup({
			log_level = "off",
			actions = {
				send = {
					compose = {
						title = " Action Compose ",
						width = "wide",
						capture_placeholders = {},
					},
				},
			},
		})

		assert.are.same({ title = " Action Compose " }, config.opts.actions.send.compose)
	end)

	it("returns structured errors for malformed runtime compose options", function()
		local validate = require("wiremux.utils.validate")
		local normalized, errors = validate.compose_options({
			on_new_payload = "merge",
			capture_placeholders = { "file" },
			keymaps = { send = { "<CR>", mode = "bad" } },
		}, { path = "item.compose" })

		assert.are.same({}, normalized)
		assert.are.equal(3, #errors)
		local paths = {}
		for _, err in ipairs(errors) do
			paths[err.path] = true
			assert.is_string(err.message)
		end
		assert.is_true(paths["item.compose.on_new_payload"])
		assert.is_true(paths["item.compose.capture_placeholders"])
		assert.is_true(paths["item.compose.keymaps.send.mode"])
	end)

	it("resolves enabled compose values to session-only config", function()
		local validate = require("wiremux.utils.validate")
		local global = {
			width = 0.6,
			height = 0.4,
			title = " Global ",
			capture_placeholders = { "file" },
			wo = { wrap = true, number = false },
		}

		local resolved, errors = validate.resolve_compose(global, {
			title = " Runtime ",
			wo = { number = true },
		}, "opts.compose")

		assert.are.same({}, errors)
		assert.are.equal(0.6, resolved.width)
		assert.are.equal(" Runtime ", resolved.title)
		assert.are.same({ wrap = true, number = true }, resolved.wo)
		assert.is_nil(resolved.capture_placeholders)
	end)

	it("captures lightweight defaults while resolving uncaptured names later", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		local state = "source"
		local calls = { file = 0, buffers = 0, quickfix = 0 }
		config.setup({
			log_level = "off",
			context = {
				resolvers = {
					file = function()
						calls.file = calls.file + 1
						return state .. "-file"
					end,
					filename = function() return "filename" end,
					position = function() return "position" end,
					line = function() return "line" end,
					selection = function() return "selection" end,
					this = function() return "this" end,
					buffers = function()
						calls.buffers = calls.buffers + 1
						return state .. "-buffers"
					end,
					quickfix = function()
						calls.quickfix = calls.quickfix + 1
						return state .. "-quickfix"
					end,
				},
			},
		})
		local context = require("wiremux.context")
		local stored = context.capture("", config.opts.ui.compose.capture_placeholders)
		state = "compose"

		local working = context.extend(stored, "{file} {buffers} {quickfix}")
		local materialized = context.materialize("{file} {buffers} {quickfix}", working)

		assert.are.equal("source-file compose-buffers compose-quickfix", materialized)
		assert.are.same({ file = 1, buffers = 1, quickfix = 1 }, calls)
		assert.are.same({ file = "source-file" }, { file = stored.values.file })
		assert.is_nil(stored.values.buffers)
		assert.is_nil(stored.values.quickfix)

		config.setup()
	end)
end)
