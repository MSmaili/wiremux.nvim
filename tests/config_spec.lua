---@module 'luassert'

describe("compose configuration", function()
	it("accepts append and rejects unknown payload policies", function()
		local validate = require("wiremux.utils.validate")
		local valid_errors = validate.validate({
			log_level = "warn",
			ui = { compose = { on_new_payload = "append" } },
		})
		local invalid_errors = validate.validate({
			log_level = "warn",
			ui = { compose = { on_new_payload = "merge" } },
		})

		assert.are.same({}, valid_errors)
		assert.are.equal(1, #invalid_errors)
		assert.matches("invalid on_new_payload", invalid_errors[1])
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
end)
