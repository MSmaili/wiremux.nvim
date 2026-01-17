---@module 'luassert'

describe("context", function()
	local context

	before_each(function()
		context = require("wiremux.context")
	end)

	describe("register", function()
		it("registers custom resolver", function()
			context.register("custom", function()
				return "custom_value"
			end)
			assert.are.equal("custom_value", context.get("custom"))
		end)
	end)

	describe("get", function()
		it("returns value from resolver", function()
			context.register("test_var", function()
				return "test_value"
			end)
			assert.are.equal("test_value", context.get("test_var"))
		end)

		it("returns nil for unknown variable", function()
			assert.is_nil(context.get("nonexistent"))
		end)

		it("returns nil for empty string", function()
			context.register("empty", function()
				return ""
			end)
			assert.is_nil(context.get("empty"))
		end)

		it("returns nil on resolver error", function()
			context.register("error_fn", function()
				error("test error")
			end)
			assert.is_nil(context.get("error_fn"))
		end)
	end)

	describe("expand", function()
		before_each(function()
			context.register("var1", function()
				return "value1"
			end)
			context.register("var2", function()
				return "value2"
			end)
		end)

		it("returns text unchanged when no placeholders", function()
			assert.are.equal("plain text", context.expand("plain text"))
		end)

		it("expands single placeholder", function()
			assert.are.equal("text value1 end", context.expand("text {var1} end"))
		end)

		it("expands multiple placeholders", function()
			assert.are.equal("value1 and value2", context.expand("{var1} and {var2}"))
		end)

		it("caches repeated placeholder lookups", function()
			local call_count = 0
			context.register("cached", function()
				call_count = call_count + 1
				return "cached_value"
			end)

			context.expand("{cached} {cached} {cached}")
			assert.are.equal(1, call_count)
		end)

		it("keeps unknown placeholders", function()
			assert.are.equal("{unknown}", context.expand("{unknown}"))
		end)

		it("handles mixed known and unknown placeholders", function()
			assert.are.equal("value1 {unknown} value2", context.expand("{var1} {unknown} {var2}"))
		end)
	end)
end)
