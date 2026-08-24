---@module 'luassert'

local placeholder = require("wiremux.placeholder")

local function disabled_capture()
	return { enabled = false, results = {} }
end

describe("placeholder context", function()
	local context

	before_each(function()
		context = require("wiremux.context")
		context.configure({})
	end)

	describe("resolver registry", function()
		it("replaces custom resolvers while preserving builtins", function()
			context.configure({
				first_custom = function()
					return "first"
				end,
			})
			assert.are.equal("first", context.get("first_custom"))
			assert.is_not_nil(context.get("position"))

			context.configure({
				second_custom = function()
					return "second"
				end,
			})
			assert.is_nil(context.get("first_custom"))
			assert.are.equal("second", context.get("second_custom"))
			assert.is_not_nil(context.get("position"))
		end)

		it("allows custom resolvers to override builtins and restores fallback", function()
			context.configure({
				file = function()
					return "override"
				end,
			})
			assert.are.equal("override", context.get("file"))

			context.configure({})
			assert.are_not.equal("override", context.get("file"))
		end)

		it("omits invalid resolver definitions", function()
			context.configure({
				valid_name = function()
					return "valid"
				end,
				["bad-name"] = function()
					return "invalid"
				end,
				invalid_value = "not a function",
			})

			assert.are.equal("valid", context.get("valid_name"))
			assert.is_nil(context.get("bad-name"))
			assert.is_nil(context.get("invalid_value"))
		end)
	end)

	describe("page origin", function()
		it("captures the source selection once", function()
			local builtins = require("wiremux.context.builtins")
			local selection = builtins.selection
			builtins.selection = function()
				return "selected text"
			end

			local origin = context.capture_origin()
			builtins.selection = selection

			assert.are.equal("selected text", origin.selection)
		end)
	end)

	describe("resolver outcomes", function()
		it("returns strings including empty strings", function()
			context.configure({
				value = function()
					return "resolved"
				end,
				empty = function()
					return ""
				end,
			})

			assert.are.equal("resolved", context.get("value"))
			assert.are.equal("", context.get("empty"))
			assert.is_true(context.is_available("value"))
			assert.is_false(context.is_available("empty"))
		end)

		it("treats unknown, nil, failed, and non-string results as unresolved", function()
			context.configure({
				nil_value = function()
					return nil
				end,
				failed = function()
					error("failed")
				end,
				invalid = function()
					return 42
				end,
			})

			assert.is_nil(context.get("unknown"))
			assert.is_nil(context.get("nil_value"))
			assert.is_nil(context.get("failed"))
			assert.is_nil(context.get("invalid"))
			assert.is_false(context.is_available("unknown"))
		end)
	end)

	describe("capture", function()
		it("stores empty strings and materializes them to empty text", function()
			context.configure({
				empty = function()
					return ""
				end,
			})

			local capture = context.capture("before {empty} after")

			assert.are.same({ empty = "" }, capture.results)
			assert.are.equal("before  after", context.materialize("before {empty} after", capture))
		end)

		it("records every attempted name and preserves unresolved tokens", function()
			context.configure({
				failed = function()
					error("failed")
				end,
				nil_value = function()
					return nil
				end,
				invalid = function()
					return false
				end,
			})
			local text = "{unknown} {failed} {nil_value} {invalid}"

			local capture = context.capture(text)

			assert.are.same({ unknown = false, failed = false, nil_value = false, invalid = false }, capture.results)
			assert.are.equal(text, context.materialize(text, capture))
		end)

		it("resolves repeated names once in sorted order", function()
			local calls = {}
			context.configure({
				zeta = function()
					table.insert(calls, "zeta")
					return "z"
				end,
				alpha = function()
					table.insert(calls, "alpha")
					return "a"
				end,
			})

			local capture = context.capture("{zeta} {alpha} {zeta}")

			assert.are.same({ "alpha", "zeta" }, calls)
			assert.are.same({ alpha = "a", zeta = "z" }, capture.results)
		end)

		it("does no resolver work when no placeholders are requested", function()
			local calls = 0
			context.configure({
				unused = function()
					calls = calls + 1
					return "unused"
				end,
			})

			local capture = context.capture("plain text")

			assert.are.equal(0, calls)
			assert.are.same({ enabled = true, results = {} }, capture)
		end)
	end)

	describe("extend", function()
		it("adds new names without mutating the stored capture", function()
			local current = { seeded = "creation", added = "confirmation" }
			context.configure({
				seeded = function()
					return current.seeded
				end,
				added = function()
					return current.added
				end,
			})
			local stored = context.capture("{seeded}")
			current.seeded = "changed"

			local extended = context.extend(stored, "{seeded} {added}")

			assert.are.same({ seeded = "creation" }, stored.results)
			assert.are.same({ seeded = "creation", added = "confirmation" }, extended.results)
			assert.are.equal("creation confirmation", context.materialize("{seeded} {added}", extended))
		end)

		it("uses a copied page origin for late built-in and custom resolvers", function()
			local received_origin
			context.configure({
				custom = function(origin)
					received_origin = origin
					origin.path = "mutated"
					return "custom"
				end,
			})
			local command, system_options
			local system = vim.system
			vim.system = function(args, options)
				command, system_options = args, options
				return {
					wait = function()
						return { code = 0, stdout = "diff" }
					end,
				}
			end
			local origin = { bufnr = -1, path = "/project/source.lua", row = 4, col = 2, selection = "" }

			local ok, extended = pcall(context.extend, context.capture("plain"), "{changes} {custom}", origin)
			vim.system = system

			assert(ok, extended)
			assert.are.same({ "git", "diff", "HEAD", "--", "/project/source.lua" }, command)
			assert.are.same({ text = true, cwd = "/project" }, system_options)
			assert.are.equal("diff", extended.results.changes)
			assert.are.same({ bufnr = -1, path = "mutated", row = 4, col = 2, selection = "" }, received_origin)
			assert.are.equal("/project/source.lua", origin.path)
		end)

		it("keeps the captured path while using a live or reopened origin buffer", function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/wiremux-origin.lua")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "first", "source line" })
			local namespace = vim.api.nvim_create_namespace("wiremux-origin-test")
			vim.diagnostic.set(namespace, bufnr, {
				{ lnum = 1, col = 1, message = "origin problem", severity = vim.diagnostic.severity.ERROR },
			})
			local origin = {
				bufnr = bufnr,
				path = vim.api.nvim_buf_get_name(bufnr),
				row = 2,
				col = 0,
				selection = "chosen text",
			}
			vim.api.nvim_buf_set_name(bufnr, "/tmp/wiremux-renamed.lua")

			local extended = context.extend(
				context.capture("plain"),
				"{file} {filename} {position} {line} {selection} {this} {diagnostics} {diagnostics_all}",
				origin
			)

			assert.are.equal(origin.path, extended.results.file)
			assert.are.equal("wiremux-origin.lua", extended.results.filename)
			assert.are.equal(origin.path .. ":2:1", extended.results.position)
			assert.are.equal("source line", extended.results.line)
			assert.are.equal("chosen text", extended.results.selection)
			assert.are.equal(origin.path .. ":2:1\nchosen text", extended.results.this)
			assert.matches("/tmp/wiremux%-origin.lua", extended.results.diagnostics)
			assert.matches("origin problem", extended.results.diagnostics_all)
			vim.api.nvim_buf_delete(bufnr, { force = true })
			assert.are.same(
				{ line = false, diagnostics = false },
				context.extend(context.capture("plain"), "{line} {diagnostics}", origin).results
			)

			local reopened = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(reopened, origin.path)
			vim.api.nvim_buf_set_lines(reopened, 0, -1, false, { "first", "reopened line" })
			assert.are.equal("reopened line", context.extend(context.capture("plain"), "{line}", origin).results.line)
			vim.api.nvim_buf_delete(reopened, { force = true })
		end)

		it("matches a reopened buffer path literally", function()
			local collision = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(collision, "/tmp/wiremux-x.lua")
			vim.api.nvim_buf_set_lines(collision, 0, -1, false, { "collision" })
			local exact = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(exact, "/tmp/wiremux-[x].lua")
			vim.api.nvim_buf_set_lines(exact, 0, -1, false, { "exact" })
			local origin = {
				bufnr = -1,
				path = vim.api.nvim_buf_get_name(exact),
				row = 1,
				col = 0,
				selection = "",
			}

			local extended = context.extend(context.capture("plain"), "{line}", origin)

			assert.are.equal("exact", extended.results.line)
			vim.api.nvim_buf_delete(collision, { force = true })
			vim.api.nvim_buf_delete(exact, { force = true })
		end)

		it("preserves current-context changes options when no origin is supplied", function()
			local current = vim.api.nvim_get_current_buf()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(bufnr, "/tmp/wiremux-direct.lua")
			vim.api.nvim_set_current_buf(bufnr)
			local options
			local system = vim.system
			vim.system = function(_, value)
				options = value
				return {
					wait = function()
						return { code = 0, stdout = "diff" }
					end,
				}
			end

			context.get("changes")
			vim.system = system
			vim.api.nvim_set_current_buf(current)
			vim.api.nvim_buf_delete(bufnr, { force = true })

			assert.are.same({ text = true }, options)
		end)

		it("never retries a failed eager capture", function()
			local calls = 0
			local available = false
			context.configure({
				eager = function()
					calls = calls + 1
					return available and "late" or nil
				end,
			})
			local stored = context.capture("{eager}")
			available = true

			local extended = context.extend(stored, "{eager}")

			assert.are.equal(1, calls)
			assert.are.same({ eager = false }, extended.results)
			assert.are.equal("{eager}", context.materialize("{eager}", extended))
		end)

		it("records new attempts as strings or unavailable results", function()
			context.configure({
				empty = function()
					return ""
				end,
				nil_value = function()
					return nil
				end,
				failed = function()
					error("failed")
				end,
				invalid = function()
					return {}
				end,
			})

			local extended =
				context.extend(context.capture("plain"), "{empty} {nil_value} {failed} {invalid} {unknown}")

			assert.are.same({
				empty = "",
				nil_value = false,
				failed = false,
				invalid = false,
				unknown = false,
			}, extended.results)
		end)

		it("resolves repeated new names once in sorted order", function()
			local calls = {}
			context.configure({
				second = function()
					table.insert(calls, "second")
					return "2"
				end,
				first = function()
					table.insert(calls, "first")
					return "1"
				end,
			})

			local extended = context.extend(context.capture("plain"), "{second} {first} {second}")

			assert.are.same({ "first", "second" }, calls)
			assert.are.same({ first = "1", second = "2" }, extended.results)
		end)

		it("clones disabled captures and leaves text literal", function()
			local stored = disabled_capture()
			local extended = context.extend(stored, "{file}")

			assert.are_not.equal(stored, extended)
			assert.are_not.equal(stored.results, extended.results)
			assert.are.equal("{file}", context.materialize("{file}", extended))
		end)
	end)

	describe("materialize", function()
		it("never invokes a resolver", function()
			local calls = 0
			context.configure({
				value = function()
					calls = calls + 1
					return "resolved"
				end,
			})
			local capture = context.capture("{value}")
			calls = 0

			assert.are.equal("resolved resolved", context.materialize("{value} {value}", capture))
			assert.are.equal(0, calls)
		end)

		it("rejects malformed captures", function()
			assert.has_error(function()
				context.extend(nil, "text")
			end)
			assert.has_error(function()
				context.materialize("text", nil)
			end)
			assert.has_error(function()
				context.materialize("{value}", { enabled = true, results = { value = true } })
			end)
		end)
	end)
end)

describe("placeholder grammar", function()
	it("aligns validation, discovery, materialization, and Vim highlighting", function()
		local context = require("wiremux.context")
		local cases = {
			{ name = "name", valid = true },
			{ name = "_name2", valid = true },
			{ name = "1name", valid = false },
			{ name = "bad-name", valid = false },
			{ name = "", valid = false },
		}

		for _, case in ipairs(cases) do
			local token = "{" .. case.name .. "}"
			local discovered = placeholder.discover(token)
			local capture = {
				enabled = true,
				results = case.valid and { [case.name] = "resolved" } or {},
			}
			local regex = vim.regex(placeholder.vim_highlight_pattern)
			local start_index, end_index = regex:match_str(token)
			local highlighted = start_index == 0 and end_index == #token

			assert.are.equal(case.valid, placeholder.is_valid_name(case.name))
			assert.are.same(case.valid and { case.name } or {}, discovered)
			assert.are.equal(case.valid and "resolved" or token, context.materialize(token, capture))
			assert.are.equal(case.valid, highlighted)
		end
	end)
end)
