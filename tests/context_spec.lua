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

	describe("resolve", function()
		it("removes a placeholder that resolves to an empty string", function()
			context.configure({
				empty = function()
					return ""
				end,
			})

			assert.are.equal("before  after", context.resolve("before {empty} after"))
		end)

		it("keeps unknown, failed, nil and non-string names literal", function()
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

			assert.are.equal(text, context.resolve(text))
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

			assert.are.equal("z a z", context.resolve("{zeta} {alpha} {zeta}"))
			assert.are.same({ "alpha", "zeta" }, calls)
		end)

		it("does no resolver work when the text has no placeholder", function()
			local calls = 0
			context.configure({
				unused = function()
					calls = calls + 1
					return "unused"
				end,
			})

			assert.are.equal("plain text", context.resolve("plain text"))
			assert.are.equal(0, calls)
		end)

		it("retries a name that was unavailable in an earlier resolve", function()
			local available = false
			context.configure({
				late = function()
					return available and "ready" or nil
				end,
			})

			assert.are.equal("{late}", context.resolve("{late}"))
			available = true
			assert.are.equal("ready", context.resolve("{late}"))
		end)

		it("passes a copied origin to built-in and custom resolvers", function()
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
			local origin = {
				bufnr = -1,
				path = "/project/source.lua",
				row = 4,
				col = 2,
				selection = "",
				line = "",
			}

			local ok, payload = pcall(context.resolve, "{changes} {custom}", origin)
			vim.system = system

			assert(ok, payload)
			assert.are.equal("diff custom", payload)
			assert.are.same({ "git", "diff", "HEAD", "--", "/project/source.lua" }, command)
			assert.are.same({ text = true, cwd = "/project" }, system_options)
			assert.are.same({
				bufnr = -1,
				path = "mutated",
				row = 4,
				col = 2,
				selection = "",
				line = "",
			}, received_origin)
			assert.are.equal("/project/source.lua", origin.path)
		end)

		it("keeps frozen values and degrades only buffer-dependent names", function()
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
				line = "source line",
			}
			vim.api.nvim_buf_set_name(bufnr, "/tmp/wiremux-renamed.lua")

			assert.are.equal(origin.path, context.resolve("{file}", origin))
			assert.are.equal("wiremux-origin.lua", context.resolve("{filename}", origin))
			assert.are.equal(origin.path .. ":2:1", context.resolve("{position}", origin))
			assert.are.equal("source line", context.resolve("{line}", origin))
			assert.are.equal("chosen text", context.resolve("{selection}", origin))
			assert.are.equal(origin.path .. ":2:1\nchosen text", context.resolve("{this}", origin))
			assert.matches("origin problem", context.resolve("{diagnostics}", origin))
			assert.matches("origin problem", context.resolve("{diagnostics_all}", origin))

			vim.api.nvim_buf_delete(bufnr, { force = true })

			-- The line is frozen in the origin, so only buffer-dependent names degrade.
			assert.are.equal("source line {diagnostics}", context.resolve("{line} {diagnostics}", origin))

			local reopened = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(reopened, origin.path)
			vim.api.nvim_buf_set_lines(reopened, 0, -1, false, { "first", "reopened line" })
			vim.diagnostic.set(namespace, reopened, {
				{ lnum = 1, col = 1, message = "reopened problem", severity = vim.diagnostic.severity.ERROR },
			})
			assert.matches("reopened problem", context.resolve("{diagnostics}", origin))
			vim.api.nvim_buf_delete(reopened, { force = true })
		end)

		it("matches a reopened buffer path literally", function()
			local namespace = vim.api.nvim_create_namespace("wiremux-literal-path-test")
			local collision = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(collision, "/tmp/wiremux-x.lua")
			vim.diagnostic.set(namespace, collision, {
				{ lnum = 0, col = 0, message = "collision problem", severity = vim.diagnostic.severity.ERROR },
			})
			local exact = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(exact, "/tmp/wiremux-[x].lua")
			vim.diagnostic.set(namespace, exact, {
				{ lnum = 0, col = 0, message = "exact problem", severity = vim.diagnostic.severity.ERROR },
			})
			local origin = {
				bufnr = -1,
				path = vim.api.nvim_buf_get_name(exact),
				row = 1,
				col = 0,
				selection = "",
				line = "exact",
			}

			assert.matches("exact problem", context.resolve("{diagnostics}", origin))
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
			context.configure(case.valid and {
				[case.name] = function()
					return "resolved"
				end,
			} or {})
			local regex = vim.regex(placeholder.vim_highlight_pattern)
			local start_index, end_index = regex:match_str(token)
			local highlighted = start_index == 0 and end_index == #token

			assert.are.equal(case.valid, placeholder.is_valid_name(case.name))
			assert.are.same(case.valid and { case.name } or {}, discovered)
			assert.are.equal(case.valid and "resolved" or token, context.resolve(token))
			assert.are.equal(case.valid, highlighted)
		end
		context.configure()
	end)
end)
