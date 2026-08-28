---@module 'luassert'

describe("compose configuration", function()
	it("accepts append and rejects unknown payload policies", function()
		local compose_config = require("wiremux.ui.compose.config")
		local _, valid_errors = compose_config.options({ on_new_payload = "append" })
		local _, invalid_errors = compose_config.options({ on_new_payload = "merge" })

		assert.are.same({}, valid_errors)
		assert.are.equal(1, #invalid_errors)
		assert.matches("invalid on_new_payload", invalid_errors[1].message)
	end)

	it("provides compose page keymap defaults", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup()

		assert.are.equal("<C-p>", config.opts.ui.compose.keymaps.previous[1])
		assert.are.equal("<C-n>", config.opts.ui.compose.keymaps.next[1])
		assert.are.equal("<C-x>", config.opts.ui.compose.keymaps.delete_page[1])
		assert.are.equal("A", config.opts.ui.compose.keymaps.append_next[1])
		assert.are.equal("K", config.opts.ui.compose.keymaps.preview_placeholder[1])
	end)

	it("owns its option tree instead of aliasing module defaults", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")

		config.setup({ log_level = "off" })
		config.opts.ui.compose.title = " Mutated "
		config.opts.actions.send.behavior = "all"
		config.setup({ log_level = "off" })

		assert.are.equal(" Compose Message ", config.opts.ui.compose.title)
		assert.are.equal("pick", config.opts.actions.send.behavior)
	end)

	it("replaces custom resolvers on repeated setup", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		local context = require("wiremux.context")

		config.setup({
			log_level = "off",
			context = { resolvers = {
				first = function()
					return "first"
				end,
			} },
		})
		assert.are.equal("first", context.get("first"))

		config.setup({
			log_level = "off",
			context = { resolvers = {
				second = function()
					return "second"
				end,
			} },
		})
		assert.is_nil(context.get("first"))
		assert.are.equal("second", context.get("second"))
		assert.is_not_nil(context.get("position"))

		config.setup()
	end)

	it("validates resolver names with the placeholder grammar", function()
		local validate = require("wiremux.utils.validate")
		local errors = validate.validate({
			context = { resolvers = {
				["bad-name"] = function()
					return "invalid"
				end,
			} },
		})

		assert.are.equal(1, #errors)
		assert.are.equal("context.resolvers.bad-name", errors[1].path)
		assert.matches("resolver name", errors[1].message)
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
					keymaps = { send = { "<C-x>", mode = "invalid" } },
				},
			},
		})

		assert.are.equal(0.6, config.opts.ui.compose.width)
		assert.are.equal("ask", config.opts.ui.compose.close_behavior)
		assert.are.equal("<C-s>", config.opts.ui.compose.keymaps.send[1][1])
	end)

	it("normalizes action-default compose tables", function()
		package.loaded["wiremux.config"] = nil
		local config = require("wiremux.config")
		config.setup({
			log_level = "off",
			actions = {
				send = {
					compose = {
						title = " Action Compose ",
						width = "wide",
					},
				},
			},
		})

		assert.are.same({ title = " Action Compose " }, config.opts.actions.send.compose)
	end)

	it("returns structured errors for malformed runtime compose options", function()
		local compose_config = require("wiremux.ui.compose.config")
		local normalized, errors = compose_config.options({
			on_new_payload = "merge",
			capture_placeholders = { "file" },
			keymaps = { send = { "<CR>", mode = "bad" } },
		}, "item.compose")

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
		local compose_config = require("wiremux.ui.compose.config")
		local global = {
			width = 0.6,
			height = 0.4,
			title = " Global ",
			wo = { wrap = true, number = false },
		}

		local resolved, errors = compose_config.resolve(global, {
			title = " Runtime ",
			wo = { number = true },
		}, "opts.compose")

		assert.are.same({}, errors)
		assert.are.equal(0.6, resolved.width)
		assert.are.equal(" Runtime ", resolved.title)
		assert.are.same({ wrap = true, number = true }, resolved.wo)
	end)
end)
