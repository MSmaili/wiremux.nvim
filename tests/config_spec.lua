---@module 'luassert'

local compose_config = require("wiremux.ui.compose.config")
local keymaps = require("wiremux.ui.compose.keymaps")

describe("configuration", function()
	local config
	local original_config
	local original_context

	before_each(function()
		original_config = package.loaded["wiremux.config"]
		original_context = package.loaded["wiremux.context"]
		package.loaded["wiremux.config"] = nil
		package.loaded["wiremux.context"] = nil
		config = require("wiremux.config")
		config.setup({ log_level = "off" })
	end)

	after_each(function()
		package.loaded["wiremux.config"] = original_config
		package.loaded["wiremux.context"] = original_context
	end)

	describe("default compose keybindings", function()
		it("sends with normal-mode <CR>", function()
			assert.are.equal("<CR>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
		end)

		it("has no insert-mode send binding", function()
			assert.is_nil(keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "i"))
		end)

		it("uses <C-s> for append-next in normal mode only", function()
			local bindings = keymaps.normalize(config.opts.ui.compose.keymaps.append_next)

			assert.are.equal(1, #bindings)
			assert.are.equal("<C-s>", bindings[1].key)
			assert.are.same({ "n" }, bindings[1].modes)
		end)

		it("navigates pages with normal-mode <C-p> and <C-n>", function()
			assert.are.equal("<C-p>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.previous, "n"))
			assert.are.equal("<C-n>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.next, "n"))
		end)

		it("deletes the current page with normal-mode <C-x>", function()
			assert.are.equal("<C-x>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.delete_page, "n"))
		end)

		it("previews placeholders with normal-mode K", function()
			assert.are.equal("K", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.preview_placeholder, "n"))
		end)
	end)

	describe("default compose options", function()
		it("uses sixty percent of the editor width", function()
			assert.are.equal(0.6, config.opts.ui.compose.width)
		end)

		it("asks before closing a draft", function()
			assert.are.equal("ask", config.opts.ui.compose.close_behavior)
		end)
	end)

	describe("compose payload policies", function()
		it("accepts append", function()
			local normalized, errors = compose_config.options({ on_new_payload = "append" })

			assert.are.same({}, errors)
			assert.are.equal("append", normalized.on_new_payload)
		end)

		it("rejects an unknown policy", function()
			local normalized, errors = compose_config.options({ on_new_payload = "merge" }, "item.compose")

			assert.is_nil(normalized.on_new_payload)
			assert.are.equal(1, #errors)
			assert.are.equal("item.compose.on_new_payload", errors[1].path)
			assert.matches("invalid on_new_payload", errors[1].message)
		end)
	end)

	describe("compose history limit", function()
		it("defaults to four retained sends", function()
			assert.are.equal(4, config.opts.ui.compose.history_limit)
		end)

		it("accepts zero to disable history globally", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = 0 }, { history_limit = 7 })

			assert.are.same({}, errors)
			assert.are.equal(0, normalized.history_limit)
		end)

		it("accepts a positive integer globally", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = 2 }, { history_limit = 7 })

			assert.are.same({}, errors)
			assert.are.equal(2, normalized.history_limit)
		end)

		it("rejects a negative limit and keeps the default", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = -1 }, { history_limit = 7 })

			assert.are.equal(7, normalized.history_limit)
			assert.are.equal(1, #errors)
			assert.are.equal("ui.compose.history_limit", errors[1].path)
			assert.matches("non%-negative integer", errors[1].message)
		end)

		it("rejects a fractional limit and keeps the default", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = 1.5 }, { history_limit = 7 })

			assert.are.equal(7, normalized.history_limit)
			assert.are.equal(1, #errors)
			assert.are.equal("ui.compose.history_limit", errors[1].path)
			assert.matches("non%-negative integer", errors[1].message)
		end)

		it("rejects a runtime history override", function()
			local resolved, errors = compose_config.resolve(
				{ history_limit = 7 },
				{ history_limit = 0 },
				"item.compose"
			)

			assert.is_nil(resolved)
			assert.are.equal(1, #errors)
			assert.are.equal("item.compose.history_limit", errors[1].path)
			assert.matches("unknown compose option", errors[1].message)
		end)

		it("does not copy the global history limit into a session", function()
			local resolved, errors = compose_config.resolve({ history_limit = 7 }, true, "opts.compose")

			assert.are.same({}, errors)
			assert.is_nil(resolved.history_limit)
		end)
	end)

	describe("repeated setup", function()
		it("owns its option tree instead of aliasing module defaults", function()
			config.opts.ui.compose.title = " Mutated "
			config.opts.actions.send.behavior = "all"

			config.setup({ log_level = "off" })

			assert.are.equal(" Compose Message ", config.opts.ui.compose.title)
			assert.are.equal("pick", config.opts.actions.send.behavior)
		end)

		it("replaces custom resolvers while preserving builtins", function()
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
		end)
	end)

	describe("custom resolver validation", function()
		it("rejects names outside the placeholder grammar", function()
			local errors = require("wiremux.utils.validate").validate({
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
	end)

	describe("malformed global compose options with logging off", function()
		it("falls back to the default width", function()
			local default_width = config.opts.ui.compose.width

			config.setup({ log_level = "off", ui = { compose = { width = "wide" } } })

			assert.are.equal(default_width, config.opts.ui.compose.width)
		end)

		it("falls back to the default close behavior", function()
			local default_close_behavior = config.opts.ui.compose.close_behavior

			config.setup({ log_level = "off", ui = { compose = { close_behavior = "explode" } } })

			assert.are.equal(default_close_behavior, config.opts.ui.compose.close_behavior)
		end)

		it("falls back to the default send binding for an invalid mapping mode", function()
			local default_send_key = keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n")

			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { send = { "<F8>", mode = "invalid" } } } },
			})

			assert.are.equal(default_send_key, keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
		end)
	end)

	describe("compose option normalization", function()
		it("keeps valid action defaults while dropping malformed fields", function()
			config.setup({
				log_level = "off",
				actions = { send = { compose = { title = " Action Compose ", width = "wide" } } },
			})

			assert.are.same({ title = " Action Compose " }, config.opts.actions.send.compose)
		end)

		it("reports every malformed runtime option with its path and message", function()
			local normalized, errors = compose_config.options({
				on_new_payload = "merge",
				capture_placeholders = { "file" },
				keymaps = { send = { "<F8>", mode = "bad" } },
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

		it("merges runtime overrides with global session fields", function()
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
			assert.are.equal(" Global ", global.title)
			assert.are.same({ wrap = true, number = false }, global.wo)
		end)
	end)
end)
