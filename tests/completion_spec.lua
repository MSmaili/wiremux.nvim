---@module 'luassert'

describe("placeholder completion", function()
	local original_modules, original_cmp, buffers_before

	before_each(function()
		original_modules = {}
		for name, module in pairs(package.loaded) do
			if name:match("^wiremux") then
				original_modules[name] = module
				package.loaded[name] = nil
			end
		end
		original_cmp = package.loaded.cmp
		buffers_before = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			buffers_before[buf] = true
		end
	end)

	after_each(function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if not buffers_before[buf] and vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		for name in pairs(package.loaded) do
			if name:match("^wiremux") then
				package.loaded[name] = nil
			end
		end
		for name, module in pairs(original_modules) do
			package.loaded[name] = module
		end
		package.loaded.cmp = original_cmp
	end)

	local function open(text, resolve, origin)
		local compose = require("wiremux.ui.compose")
		local config = vim.deepcopy(require("wiremux.config").opts.ui.compose)
		config.on_new_payload = "append"
		config.close_behavior = "hide"
		compose.open(text, {
			config = config,
			source = { resolve = resolve ~= false, origin = origin },
			on_confirm = function() end,
		})
		return compose.get_buf()
	end

	local function mapping(key)
		vim.fn.maparg(key, "n", false, true).callback()
	end

	local function find(items, label)
		for _, item in ipairs(items) do
			if item.label == label then
				return item
			end
		end
		error("Missing completion: " .. label)
	end

	it("keeps adapter construction and ordinary-buffer requests free of runtime dependencies", function()
		local blink = require("wiremux.completion.blink").new()
		local cmp = require("wiremux.completion.cmp").new()
		assert.is_false(blink:enabled())
		assert.is_false(cmp:is_available())
		local response
		blink:get_completions({ bufnr = vim.api.nvim_get_current_buf(), line = "{", cursor = { 1, 1 } }, function(value)
			response = value
		end)
		assert.are.same({}, response.items)
		for name in pairs(package.loaded) do
			if name:match("^wiremux") then
				assert.matches("^wiremux%.completion", name)
			end
		end
		assert.are.equal(original_cmp, package.loaded.cmp)
	end)

	it("discovers custom resolvers and reconfiguration without evaluating them", function()
		local buf = open("{")
		local context = require("wiremux.context")
		local calls = 0
		local resolver = function()
			calls = calls + 1
			return "value"
		end
		context.configure({ project = resolver, file = resolver, ["invalid-name"] = resolver })
		local core = require("wiremux.completion")
		local items = core.items(buf, "{", 0, 1)
		assert.are.equal("Custom placeholder", find(items, "{project}").documentation.value)
		find(items, "{file}")
		local names = vim.tbl_map(function(item)
			return item.label
		end, items)
		assert.are.equal(1, #vim.tbl_filter(function(name)
			return name == "{file}"
		end, names))
		assert.is_false(vim.tbl_contains(names, "{invalid-name}"))
		context.configure({ workspace = resolver })
		items = core.items(buf, "{", 0, 1)
		find(items, "{workspace}")
		assert.is_false(vim.tbl_contains(
			vim.tbl_map(function(item)
				return item.label
			end, items),
			"{project}"
		))
		assert.are.equal(0, calls)
	end)

	for _, engine in ipairs({ "blink", "cmp" }) do
		describe(engine, function()
			local function complete(buf, line, row, col, opts)
				local adapter = require("wiremux.completion." .. engine).new(opts)
				local response
				local callback = function(value)
					response = value
				end
				if engine == "blink" then
					adapter:get_completions({ bufnr = buf, line = line, cursor = { row + 1, col } }, callback)
				else
					assert.are.equal("utf-8", adapter:get_position_encoding_kind())
					adapter:complete({
						context = { bufnr = buf, cursor_line = line, cursor = { row = row + 1, col = col + 1 } },
					}, callback)
				end
				return response.items, adapter
			end

			local function resolve(adapter, item)
				local result
				adapter:resolve(item, function(value)
					result = value
				end)
				return result
			end

			it("resolves only the requested preview against the page origin without changing the edit", function()
				local origin = { path = "/source/project.lua" }
				local buf = open("{", true, origin)
				local calls = 0
				require("wiremux.context").configure({
					project = function(source)
						calls = calls + 1
						local path = source.path
						source.path = "mutated"
						return path
					end,
					other = function()
						calls = calls + 100
						return "unselected"
					end,
				})
				local items, adapter = complete(buf, "{", 0, 1, { preview = true })
				assert.are.equal(0, calls)
				local item = find(items, "{project}")
				local resolved = resolve(adapter, item)
				assert.are.equal(1, calls)
				assert.are.equal("markdown", resolved.documentation.kind)
				assert.matches("/source/project.lua", resolved.documentation.value, 1, true)
				assert.are.same(item.textEdit, resolved.textEdit)
				assert.are.equal("{project}", resolved.textEdit.newText)
				assert.are.equal("/source/project.lua", origin.path)
				assert.are.same({ "{" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
			end)

			it("keeps documentation side-effect-free by default", function()
				local buf = open("{")
				local calls = 0
				require("wiremux.context").configure({
					project = function()
						calls = calls + 1
						return "value"
					end,
				})
				local items, adapter = complete(buf, "{", 0, 1)
				local item = find(items, "{project}")
				assert.are.equal(item, resolve(adapter, item))
				assert.are.equal(0, calls)
			end)

			it("bounds large previews by lines and bytes without splitting UTF-8", function()
				local buf = open("{")
				require("wiremux.context").configure({
					long = function()
						return string.rep("line\n", 10000)
					end,
					unicode = function()
						return "é🐈rest"
					end,
				})
				local items, adapter = complete(buf, "{", 0, 1, { preview = { max_lines = 2, max_bytes = 12 } })
				local text = resolve(adapter, find(items, "{long}")).documentation.value
				assert.matches("```text\nline\nline\n```\n\nPreview truncated.", text, 1, true)
				items, adapter = complete(buf, "{", 0, 1, { preview = { max_lines = 2, max_bytes = 4 } })
				text = resolve(adapter, find(items, "{unicode}")).documentation.value
				assert.matches("```text\né\n```\n\nPreview truncated.", text, 1, true)
			end)

			it("renders empty, unavailable, failed and fenced results as documentation", function()
				local buf = open("{")
				require("wiremux.context").configure({
					empty = function()
						return ""
					end,
					missing = function()
						return nil
					end,
					failed = function()
						error("resolver failed")
					end,
					fenced = function()
						return "```lua\nreturn true\n```"
					end,
					changes = function()
						return "+added"
					end,
				})
				local items, adapter = complete(buf, "{", 0, 1, { preview = true })
				assert.matches("(empty)", resolve(adapter, find(items, "{empty}")).documentation.value, 1, true)
				for _, name in ipairs({ "missing", "failed" }) do
					assert.matches(
						"No value is available",
						resolve(adapter, find(items, "{" .. name .. "}")).documentation.value
					)
				end
				assert.matches(
					"````text\n```lua\nreturn true\n```\n````",
					resolve(adapter, find(items, "{fenced}")).documentation.value,
					1,
					true
				)
				assert.matches(
					"```diff\n+added\n```",
					resolve(adapter, find(items, "{changes}")).documentation.value,
					1,
					true
				)
			end)

			it("ignores preview requests from a different page or closed draft", function()
				local buf = open("{")
				local calls = 0
				require("wiremux.context").configure({
					project = function()
						calls = calls + 1
						return "value"
					end,
				})
				local items, adapter = complete(buf, "{", 0, 1, { preview = true })
				local item = find(items, "{project}")
				open("different page")
				assert.are.equal(item, resolve(adapter, item))
				mapping("<C-p>")
				mapping("q")
				assert.are.equal(item, resolve(adapter, item))
				require("wiremux.ui.compose").open("")
				mapping("Q")
				mapping("Q")
				assert.are.equal(item, resolve(adapter, item))
				assert.are.equal(0, calls)
			end)

			for _, case in ipairs({
				{ "Explain {", #"Explain {", "Explain {file}" },
				{ "Explain {fi", #"Explain {fi", "Explain {file}" },
				{ "Explain {fi} please", #"Explain {fi", "Explain {file} please" },
				{ "Explain {filename} please", #"Explain {fi", "Explain {file} please" },
				{ "é 🐈 {fi} {line}", #"é 🐈 {fi", "é 🐈 {file} {line}" },
				{ "{this}{fi}", #"{this}{fi", "{this}{file}" },
			}) do
				it("edits only the placeholder in " .. case[1], function()
					local buf = open("first line\n" .. case[1])
					local item = find(complete(buf, case[1], 1, case[2]), "{file}")
					vim.lsp.util.apply_text_edits({ item.textEdit }, buf, "utf-8")
					assert.are.same({ "first line", case[3] }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
				end)
			end

			it("does not offer placeholders outside a valid partial token", function()
				local buf = open("draft")
				for _, text in ipairs({ "plain", "{file}", "{two words", "{123", "{fi-", "{fi\t" }) do
					assert.are.same({}, complete(buf, text, 0, #text))
				end
			end)
		end)
	end

	it("follows page changes, deletion, hide/reopen, and finalization", function()
		local buf = open("enabled")
		local core = require("wiremux.completion")
		assert.is_true(vim.b[buf].wiremux_compose)
		assert.is_true(core.enabled(buf))
		open("literal", false)
		assert.is_false(core.enabled(buf))
		assert.are.same({}, core.items(buf, "{", 0, 1))
		mapping("<C-p>")
		assert.is_true(core.enabled(buf))
		mapping("<C-n>")
		assert.is_false(core.enabled(buf))
		mapping("<C-x>")
		assert.is_true(core.enabled(buf))
		mapping("q")
		assert.are.same({}, core.items(buf, "{", 0, 1))
		require("wiremux.ui.compose").open("")
		assert.is_true(core.enabled())
		mapping("Q")
		assert.is_false(core.enabled(buf))
		assert.are.same({}, core.items(buf, "{", 0, 1))
	end)

	it("registers cmp only once when explicitly requested", function()
		local registrations = 0
		package.loaded.cmp = {
			register_source = function(name, source)
				assert.are.equal("wiremux", name)
				assert.is_function(source.complete)
				registrations = registrations + 1
				return 42
			end,
		}
		local adapter = require("wiremux.completion.cmp")
		assert.are.equal(0, registrations)
		assert.are.equal(42, adapter.register())
		assert.are.equal(42, adapter.register())
		assert.are.equal(1, registrations)
	end)
end)
