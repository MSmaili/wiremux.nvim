---@module 'luassert'

local helpers = require("tests.helpers")

local function file_text(path)
	local fd = assert(vim.uv.fs_open(path, "r", 384))
	local stat = assert(vim.uv.fs_fstat(fd))
	local text = stat.size == 0 and "" or assert(vim.uv.fs_read(fd, stat.size, 0))
	vim.uv.fs_close(fd)
	return text
end

describe("compose history storage", function()
	local config
	local history
	local old_stdpath
	local state
	local root

	before_each(function()
		package.loaded["wiremux.config"] = nil
		package.loaded["wiremux.history"] = nil
		config = require("wiremux.config")
		config.setup({ log_level = "off", ui = { compose = { history_limit = 4 } } })
		old_stdpath = vim.fn.stdpath
		state = vim.fn.tempname()
		vim.fn.mkdir(state, "p")
		vim.fn.stdpath = function(name)
			return name == "state" and state or old_stdpath(name)
		end
		root = vim.fs.joinpath(state, "wiremux", "history")
		history = require("wiremux.history")
	end)

	after_each(function()
		vim.fn.stdpath = old_stdpath
		vim.fn.delete(state, "rf")
		package.loaded["wiremux.history"] = nil
	end)

	it("keeps large payloads outside the metadata index and loads one lazily", function()
		local payload = "Review these changes\n" .. string.rep("+large diff line\n", 10000) .. "literal {file}"

		assert.is_true(history.add(payload))
		assert.is_true(history.add(payload))
		local entries = assert(history.list())
		local index = file_text(vim.fs.joinpath(root, "index.json"))

		assert.are.equal(2, #entries)
		assert.are.equal(#payload, entries[1].size)
		assert.are.equal("Review these changes", entries[1].preview)
		assert.not_matches("large diff line", index)
		assert.are.equal(448, vim.uv.fs_stat(root).mode % 512)
		assert.are.equal(384, vim.uv.fs_stat(vim.fs.joinpath(root, "index.json")).mode % 512)
		assert.are.equal(384, vim.uv.fs_stat(vim.fs.joinpath(root, entries[1].file)).mode % 512)
		assert.are.equal(payload, history.read(entries[1]))
	end)

	it("keeps newest entries and prunes stored payloads when the limit changes", function()
		config.opts.ui.compose.history_limit = 3
		assert.is_true(history.add("first"))
		local first = assert(history.list())[1]
		config.opts.ui.compose.history_limit = 2
		assert.is_true(history.add("second"))
		assert.is_true(history.add("third"))

		local entries = assert(history.list())
		assert.are.equal(2, #entries)
		assert.are.equal("third", history.read(entries[1]))
		assert.are.equal("second", history.read(entries[2]))
		assert.is_nil(vim.uv.fs_stat(vim.fs.joinpath(root, first.file)))

		config.opts.ui.compose.history_limit = 0
		assert.are.same({}, assert(history.list()))
		assert.is_nil(vim.uv.fs_stat(vim.fs.joinpath(root, entries[1].file)))
		assert.is_nil(vim.uv.fs_stat(vim.fs.joinpath(root, entries[2].file)))
	end)

	it("keeps usable history when stale-file cleanup fails", function()
		assert.is_true(history.add("stored"))
		local orphan = vim.fs.joinpath(root, "orphan.txt")
		local fd = assert(vim.uv.fs_open(orphan, "w", 384))
		assert(vim.uv.fs_write(fd, "orphan", 0))
		vim.uv.fs_close(fd)
		local unlink = vim.uv.fs_unlink
		vim.uv.fs_unlink = function(path, ...)
			if path == orphan then
				return nil, "permission denied"
			end
			return unlink(path, ...)
		end

		local entries, err = history.list()
		vim.uv.fs_unlink = unlink

		assert.are.equal(1, #entries)
		assert.matches("permission denied", err)
	end)

	it("drops missing entries and unindexed files but preserves a malformed index", function()
		assert.is_true(history.add("stored"))
		local entry = assert(history.list())[1]
		assert(vim.uv.fs_unlink(vim.fs.joinpath(root, entry.file)))
		local orphan = vim.fs.joinpath(root, "orphan.txt")
		local fd = assert(vim.uv.fs_open(orphan, "w", 384))
		assert(vim.uv.fs_write(fd, "orphan", 0))
		vim.uv.fs_close(fd)
		local directory = vim.fs.joinpath(root, "preserve.txt")
		vim.fn.mkdir(directory)

		assert.are.same({}, assert(history.list()))
		assert.is_nil(vim.uv.fs_stat(orphan))
		assert.are.equal("directory", vim.uv.fs_stat(directory).type)

		local index_path = vim.fs.joinpath(root, "index.json")
		local malformed = "{not json"
		fd = assert(vim.uv.fs_open(index_path, "w", 384))
		assert(vim.uv.fs_write(fd, malformed, 0))
		vim.uv.fs_close(fd)
		local entries, err = history.list()

		assert.is_nil(entries)
		assert.matches("malformed", err)
		assert.are.equal(malformed, file_text(index_path))
	end)
end)

describe("compose history action", function()
	local MODULES = {
		"wiremux.action.history",
		"wiremux.action.send",
		"wiremux.config",
		"wiremux.history",
		"wiremux.picker",
		"wiremux.utils.notify",
	}
	local mocks

	before_each(function()
		helpers.clear(MODULES)
		mocks = {
			config = { opts = { ui = { compose = { history_limit = 4 } } } },
			history = {
				path = function(entry)
					return "/history/" .. entry.file
				end,
			},
			picker = {},
			notify = helpers.mock_notify(),
			send = {},
		}
		mocks.config.get = function()
			return mocks.config.opts
		end
		helpers.register({
			["wiremux.config"] = mocks.config,
			["wiremux.history"] = mocks.history,
			["wiremux.picker"] = mocks.picker,
			["wiremux.utils.notify"] = mocks.notify,
			["wiremux.action.send"] = mocks.send,
		})
	end)

	after_each(function()
		helpers.clear(MODULES)
	end)

	it("lists metadata and reopens only the selected payload as literal compose", function()
		local entry = {
			created_at = 0,
			preview = "Review changes",
			size = 2048,
			file = "entry.txt",
		}
		mocks.history.list = function()
			return { entry }
		end
		mocks.history.read = function(choice)
			assert.are.equal(entry, choice)
			return "resolved {file}"
		end
		local label
		mocks.picker.select = function(items, opts, callback)
			assert.are.equal("Compose history", opts.prompt)
			assert.are.equal(mocks.history.path, opts.preview_file)
			label = opts.format_item(items[1])
			callback(items[1])
		end
		local sent
		mocks.send.send = function(item)
			sent = item
		end

		require("wiremux.action.history").history()

		assert.matches("%[2%.0 KB%]", label)
		assert.matches("Review changes", label)
		assert.are.same({ value = "resolved {file}", compose = true, placeholders = false }, sent)
	end)

	it("leaves compose untouched when the picker is cancelled", function()
		mocks.history.list = function()
			return { { created_at = 0, preview = "Draft", size = 5, file = "entry.txt" } }
		end
		mocks.history.read = function()
			error("cancelled history must not be read")
		end
		mocks.picker.select = function(_, _, callback)
			callback(nil)
		end
		mocks.send.send = function()
			error("cancelled history must not open compose")
		end

		require("wiremux.action.history").history()
	end)

	it("warns without opening a picker when history is empty", function()
		mocks.history.list = function()
			return {}
		end
		mocks.picker.select = function()
			error("picker must not open")
		end
		local warning
		mocks.notify.warn = function(message)
			warning = message
		end

		require("wiremux.action.history").history()

		assert.matches("No compose history", warning)
	end)

	it("registers the Wiremux history command", function()
		local called = false
		package.loaded["wiremux.action.history"] = {
			history = function()
				called = true
			end,
		}

		vim.cmd("Wiremux history")

		assert.is_true(called)
	end)
end)
