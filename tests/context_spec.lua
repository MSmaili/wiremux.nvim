---@module 'luassert'

local placeholder = require("wiremux.placeholder")

local function disabled_capture()
	return { enabled = false, capture_set = {}, values = {} }
end

describe("placeholder context", function()
	local context

	before_each(function()
		context = require("wiremux.context")
		context.configure({})
	end)

	describe("resolver registry", function()
		it("replaces custom resolvers while preserving builtins", function()
			context.configure({ first_custom = function()
				return "first"
			end })
			assert.are.equal("first", context.get("first_custom"))
			assert.is_not_nil(context.get("position"))

			context.configure({ second_custom = function()
				return "second"
			end })
			assert.is_nil(context.get("first_custom"))
			assert.are.equal("second", context.get("second_custom"))
			assert.is_not_nil(context.get("position"))
		end)

		it("allows custom resolvers to override builtins and restores fallback", function()
			context.configure({ file = function()
				return "override"
			end })
			assert.are.equal("override", context.get("file"))

			context.configure({})
			assert.are_not.equal("override", context.get("file"))
		end)

		it("omits invalid resolver definitions and returns a sorted name copy", function()
			context.configure({
				valid_name = function()
					return "valid"
				end,
				["bad-name"] = function()
					return "invalid"
				end,
				invalid_value = "not a function",
			})

			local names = context.list()
			local sorted = vim.deepcopy(names)
			table.sort(sorted)
			assert.are.same(sorted, names)
			assert.are.equal("valid", context.get("valid_name"))
			assert.is_nil(context.get("bad-name"))
			assert.is_nil(context.get("invalid_value"))

			table.insert(names, "mutated")
			assert.is_false(vim.tbl_contains(context.list(), "mutated"))
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
			context.configure({ empty = function()
				return ""
			end })

			local capture = context.capture("before {empty} after")

			assert.are.same({ empty = true }, capture.capture_set)
			assert.are.same({ empty = "" }, capture.values)
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

			assert.are.same({ unknown = true, failed = true, nil_value = true, invalid = true }, capture.capture_set)
			assert.are.same({}, capture.values)
			assert.are.equal(text, context.materialize(text, capture))
		end)

		it("resolves repeated and explicitly captured names once in sorted order", function()
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

			local capture = context.capture("{zeta} {alpha} {zeta}", { "alpha", "zeta" })

			assert.are.same({ "alpha", "zeta" }, calls)
			assert.are.same({ alpha = "a", zeta = "z" }, capture.values)
		end)

		it("does no resolver work when no placeholders are requested", function()
			local calls = 0
			context.configure({ unused = function()
				calls = calls + 1
				return "unused"
			end })

			local capture = context.capture("plain text")

			assert.are.equal(0, calls)
			assert.are.same({ enabled = true, capture_set = {}, values = {} }, capture)
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

			assert.are.same({ seeded = true }, stored.capture_set)
			assert.are.same({ seeded = "creation" }, stored.values)
			assert.are.same({ seeded = true, added = true }, extended.capture_set)
			assert.are.same({ seeded = "creation", added = "confirmation" }, extended.values)
			assert.are.equal("creation confirmation", context.materialize("{seeded} {added}", extended))
		end)

		it("never retries a failed eager capture", function()
			local calls = 0
			local available = false
			context.configure({ eager = function()
				calls = calls + 1
				return available and "late" or nil
			end })
			local stored = context.capture("", { "eager" })
			available = true

			local extended = context.extend(stored, "{eager}")

			assert.are.equal(1, calls)
			assert.are.same({ eager = true }, extended.capture_set)
			assert.are.same({}, extended.values)
			assert.are.equal("{eager}", context.materialize("{eager}", extended))
		end)

		it("records all new attempts but stores only successful strings", function()
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

			local extended = context.extend(
				context.capture("plain"),
				"{empty} {nil_value} {failed} {invalid} {unknown}"
			)

			assert.are.same({
				empty = true,
				nil_value = true,
				failed = true,
				invalid = true,
				unknown = true,
			}, extended.capture_set)
			assert.are.same({ empty = "" }, extended.values)
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
			assert.are.same({ first = "1", second = "2" }, extended.values)
		end)

		it("clones disabled captures and leaves text literal", function()
			local stored = disabled_capture()
			local extended = context.extend(stored, "{file}")

			assert.are_not.equal(stored, extended)
			assert.are_not.equal(stored.capture_set, extended.capture_set)
			assert.are_not.equal(stored.values, extended.values)
			assert.are.equal("{file}", context.materialize("{file}", extended))
		end)
	end)

	describe("materialize", function()
		it("never invokes a resolver", function()
			local calls = 0
			context.configure({ value = function()
				calls = calls + 1
				return "resolved"
			end })
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
				context.materialize("text", { enabled = true, capture_set = {}, values = { value = "x" } })
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
				capture_set = case.valid and { [case.name] = true } or {},
				values = case.valid and { [case.name] = "resolved" } or {},
			}
			local regex = vim.regex(placeholder.vim_highlight_pattern)
			local start_index, end_index = regex:match_str(token)
			local highlighted = start_index == 0 and end_index == #token

			assert.are.equal(case.valid, placeholder.is_valid_name(case.name))
			assert.are.equal(case.valid, discovered[case.name] == true)
			assert.are.equal(case.valid and "resolved" or token, context.materialize(token, capture))
			assert.are.equal(case.valid, highlighted)
		end
	end)
end)
