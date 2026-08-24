local keymaps = require("wiremux.ui.compose.keymaps")
local notify = require("wiremux.utils.notify")
local placeholder = require("wiremux.placeholder")

local M = {}

---@class wiremux.ui.ComposeViewIntents
---@field on_wipeout fun()

---@class wiremux.ui.ComposeViewMapping
---@field mode string
---@field key string
---@field callback function
---@field desc? string

---@class wiremux.ui.ComposeView
---@field private buf number?
---@field private win number?
---@field private preview_win number?
---@field private augroup number?
---@field private config wiremux.config.ComposeSessionConfig Session-owned config, copied by compose.open; treat as read-only.
---@field private title string
---@field private owned_mappings table<string, wiremux.ui.ComposeViewMapping>
---@field private mappings_initialized boolean
---@field private intents wiremux.ui.ComposeViewIntents?
---@field private finalized boolean
---@field private applied_window_options table<string, true>

local ACTION_ORDER = { "send", "close", "discard", "files", "delete_page", "preview_placeholder", "previous", "next" }

---@param value number
---@param min_value number
---@param max_value number
---@return number
local function clamp(value, min_value, max_value)
	return math.min(math.max(value, min_value), max_value)
end

---@param view wiremux.ui.ComposeView
---@return boolean
local function buffer_is_valid(view)
	return view.buf ~= nil and vim.api.nvim_buf_is_valid(view.buf)
end

---@param view wiremux.ui.ComposeView
---@return boolean
local function window_is_valid(view)
	return view.win ~= nil and vim.api.nvim_win_is_valid(view.win)
end

---@param view wiremux.ui.ComposeView
local function close_placeholder_preview(view)
	local preview_win = view.preview_win
	view.preview_win = nil
	if preview_win and vim.api.nvim_win_is_valid(preview_win) then
		pcall(vim.api.nvim_win_close, preview_win, true)
	end
end

---@param config wiremux.config.ComposeSessionConfig
---@param title string
---@param footer string
---@return table
local function floating_window_config(config, title, footer)
	local width_ratio = clamp(tonumber(config.width) or 0.6, 0.1, 1)
	local height_ratio = clamp(tonumber(config.height) or 0.4, 0.1, 1)
	local min_width = math.min(20, vim.o.columns)
	local min_height = math.min(3, vim.o.lines)
	local width = clamp(math.floor(vim.o.columns * width_ratio), min_width, vim.o.columns)
	local height = clamp(math.floor(vim.o.lines * height_ratio), min_height, vim.o.lines)

	local window_config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = config.style,
		border = config.border,
		title = title,
		title_pos = "center",
	}
	if footer ~= "" then
		window_config.footer = footer
		window_config.footer_pos = "center"
	end
	return window_config
end

---@param view wiremux.ui.ComposeView
---@return string
local function footer_text(view)
	local current_mode = vim.fn.mode() == "i" and "i" or "n"
	local parts = {}
	local footer_keymaps = view.config.keymaps or {}
	local entries = {
		{ entry = footer_keymaps.send, label = "Send" },
		{ entry = footer_keymaps.close, label = "Close" },
		{ entry = footer_keymaps.discard, label = "Discard" },
		{ entry = footer_keymaps.files, label = "Files" },
		{ entry = footer_keymaps.delete_page, label = "Delete Page" },
	}
	for _, item in ipairs(entries) do
		local key = keymaps.find_key_for_mode(item.entry, current_mode)
		if key then
			table.insert(parts, key .. " " .. item.label)
		end
	end
	return #parts > 0 and (" " .. table.concat(parts, "  |  ") .. " ") or ""
end

---@param win number
---@param option string
local function reset_window_option(win, option)
	pcall(vim.api.nvim_win_call, win, function()
		vim.cmd("setlocal " .. option .. "&")
	end)
end

---@param view wiremux.ui.ComposeView
local function apply_window_options(view)
	if not window_is_valid(view) then
		return
	end
	local configured = view.config.wo or {}
	for option in pairs(view.applied_window_options) do
		if configured[option] == nil then
			reset_window_option(view.win, option)
		end
	end

	local applied = {}
	for option, value in pairs(configured) do
		vim.wo[view.win][option] = value
		applied[option] = true
	end
	view.applied_window_options = applied
end

---@param view wiremux.ui.ComposeView
local function apply_window_config(view)
	if not window_is_valid(view) then
		return
	end
	vim.api.nvim_win_set_config(view.win, floating_window_config(view.config, view.title, footer_text(view)))
	apply_window_options(view)
end

---@param buf number
---@param mode string
---@param key string
---@return table?
local function current_buffer_mapping(buf, mode, key)
	local mapping
	local ok = pcall(vim.api.nvim_buf_call, buf, function()
		mapping = vim.fn.maparg(key, mode, false, true)
	end)
	if not ok or type(mapping) ~= "table" or mapping.buffer ~= 1 or next(mapping) == nil then
		return nil
	end
	return mapping
end

---@param mapping table?
---@param owned wiremux.ui.ComposeViewMapping
---@return boolean
local function is_owned_mapping(mapping, owned)
	return mapping ~= nil and mapping.callback == owned.callback
end

---@param mode string
---@param key string
---@return string
local function mapping_id(mode, key)
	return mode .. "\0" .. key
end

---@param view wiremux.ui.ComposeView
---@param desired table<string, wiremux.ui.ComposeViewMapping>
local function refresh_mappings(view, desired)
	if not buffer_is_valid(view) then
		return
	end
	local buf = view.buf
	local initial_install = not view.mappings_initialized
	local next_owned = {}

	for id, owned in pairs(view.owned_mappings) do
		local current = current_buffer_mapping(buf, owned.mode, owned.key)
		if desired[id] == nil and is_owned_mapping(current, owned) then
			pcall(vim.keymap.del, owned.mode, owned.key, { buffer = buf })
		end
	end

	for id, mapping in pairs(desired) do
		local old_owned = view.owned_mappings[id]
		local current = current_buffer_mapping(buf, mapping.mode, mapping.key)
		local can_install = initial_install
			or current == nil
			or (old_owned ~= nil and is_owned_mapping(current, old_owned))
		if can_install then
			vim.keymap.set(mapping.mode, mapping.key, mapping.callback, {
				buffer = buf,
				nowait = mapping.mode == "n",
				desc = mapping.desc,
			})
			next_owned[id] = mapping
		else
			notify.debug(
				"Compose mapping %s in mode %s was replaced; preserving the current buffer mapping",
				mapping.key,
				mapping.mode
			)
		end
	end

	view.owned_mappings = next_owned
	view.mappings_initialized = true
end

---@param view wiremux.ui.ComposeView
local function move_cursor_to_end(view)
	if not buffer_is_valid(view) or not window_is_valid(view) then
		return
	end
	local last_row = vim.api.nvim_buf_line_count(view.buf)
	local last_line = vim.api.nvim_buf_get_lines(view.buf, last_row - 1, last_row, false)[1] or ""
	vim.api.nvim_win_set_cursor(view.win, { last_row, #last_line })
end

---@param view wiremux.ui.ComposeView
---@param delete_buffer boolean
---@param report_wipeout boolean
local function release(view, delete_buffer, report_wipeout)
	if view.finalized then
		return
	end
	view.finalized = true
	local buf = view.buf
	local win = view.win
	local augroup = view.augroup
	local on_wipeout = report_wipeout and view.intents and view.intents.on_wipeout or nil
	close_placeholder_preview(view)
	view.buf = nil
	view.win = nil
	view.augroup = nil
	view.intents = nil
	view.owned_mappings = {}
	view.applied_window_options = {}
	if augroup then
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
	end
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if delete_buffer and buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	if on_wipeout then
		on_wipeout()
	end
end

---@param view wiremux.ui.ComposeView
local function setup_autocmds(view)
	local group = vim.api.nvim_create_augroup("wiremux_compose_" .. view.buf, { clear = true })
	view.augroup = group

	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		buffer = view.buf,
		callback = function()
			M.refresh_footer(view)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = view.buf,
		callback = function()
			release(view, false, true)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = "*",
		callback = function(args)
			if view.win == tonumber(args.match) then
				view.win = nil
				view.applied_window_options = {}
			end
		end,
	})
end

---@param text string
---@param config wiremux.config.ComposeSessionConfig
---@param intents wiremux.ui.ComposeViewIntents
---@return wiremux.ui.ComposeView
function M.new(text, config, intents)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].filetype = "markdown"

	---@type wiremux.ui.ComposeView
	local view = {
		buf = buf,
		win = nil,
		preview_win = nil,
		augroup = nil,
		config = config,
		title = config.title or " Compose Message ",
		owned_mappings = {},
		mappings_initialized = false,
		intents = intents,
		finalized = false,
		applied_window_options = {},
	}

	vim.api.nvim_buf_call(buf, function()
		vim.cmd("syntax match WiremuxPlaceholder /" .. placeholder.vim_highlight_pattern .. "/")
		vim.cmd("highlight default link WiremuxPlaceholder Special")
	end)
	setup_autocmds(view)
	return view
end

---@param view wiremux.ui.ComposeView
---@return number?
function M.get_buf(view)
	if buffer_is_valid(view) then
		return view.buf
	end
end

---@param view wiremux.ui.ComposeView
---@return boolean
function M.is_visible(view)
	return window_is_valid(view)
end

---@param view wiremux.ui.ComposeView
---@return string?
function M.read_text(view)
	if not buffer_is_valid(view) then
		return nil
	end
	return table.concat(vim.api.nvim_buf_get_lines(view.buf, 0, -1, false), "\n")
end

---@param view wiremux.ui.ComposeView
---@return string? name
function M.placeholder_at_cursor(view)
	if not buffer_is_valid(view) or not window_is_valid(view) then
		return nil
	end
	local cursor = vim.api.nvim_win_get_cursor(view.win)
	local line = vim.api.nvim_buf_get_lines(view.buf, cursor[1] - 1, cursor[1], false)[1] or ""
	return placeholder.at(line, cursor[2])
end

---@param view wiremux.ui.ComposeView
---@return boolean focused
function M.focus_placeholder_preview(view)
	if view.preview_win and vim.api.nvim_win_is_valid(view.preview_win) then
		vim.api.nvim_set_current_win(view.preview_win)
		return true
	end
	view.preview_win = nil
	return false
end

---@param view wiremux.ui.ComposeView
---@param text string
---@param syntax string
function M.show_placeholder_preview(view, text, syntax)
	if not buffer_is_valid(view) or not window_is_valid(view) then
		return
	end
	local preview_buf, preview_win = vim.lsp.util.open_floating_preview(
		vim.split(text, "\n", { plain = true }),
		syntax,
		{ border = view.config.border }
	)
	view.preview_win = preview_win
	vim.keymap.set("n", "<Esc>", function()
		if vim.api.nvim_win_is_valid(preview_win) then
			vim.api.nvim_win_close(preview_win, true)
		end
	end, { buffer = preview_buf, silent = true })
end

---@param view wiremux.ui.ComposeView
---@param text string
function M.load_text(view, text)
	if not buffer_is_valid(view) then
		return
	end
	close_placeholder_preview(view)
	local undolevels = vim.bo[view.buf].undolevels
	vim.bo[view.buf].undolevels = -1
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, vim.split(text, "\n"))
	vim.bo[view.buf].undolevels = undolevels
end

---@param view wiremux.ui.ComposeView
---@param config wiremux.config.ComposeSessionConfig
function M.reconfigure(view, config)
	close_placeholder_preview(view)
	view.config = config
	apply_window_config(view)
end

---@param view wiremux.ui.ComposeView
---@param title string
function M.set_title(view, title)
	view.title = title
	if window_is_valid(view) then
		vim.api.nvim_win_set_config(view.win, { title = title, title_pos = "center" })
	end
end

---@param view wiremux.ui.ComposeView
function M.refresh_footer(view)
	if window_is_valid(view) then
		vim.api.nvim_win_set_config(view.win, {
			footer = footer_text(view),
			footer_pos = "center",
		})
	end
end

---@param view wiremux.ui.ComposeView
---@param handlers table<string, function>
function M.install_keymaps(view, handlers)
	local desired = {}
	for _, action in ipairs(ACTION_ORDER) do
		local handler = handlers[action]
		if handler then
			for _, keymap in ipairs(keymaps.normalize((view.config.keymaps or {})[action])) do
				for _, mode in ipairs(keymap.modes) do
					local id = mapping_id(mode, keymap.key)
					desired[id] = {
						mode = mode,
						key = keymap.key,
						callback = handler,
						desc = keymap.desc or action,
					}
				end
			end
		end
	end

	local block_history = function() end
	for _, key in ipairs({ "<C-o>", "<C-i>" }) do
		local id = mapping_id("n", key)
		desired[id] = {
			mode = "n",
			key = key,
			callback = block_history,
			desc = "Disable compose history navigation",
		}
	end
	refresh_mappings(view, desired)
	M.refresh_footer(view)
end

---@param view wiremux.ui.ComposeView
---@param reopened boolean
---@return boolean opened
---@return { buf: number, win: number, reopened: boolean }? event_data
function M.show(view, reopened)
	if not buffer_is_valid(view) then
		return false, nil
	end
	local opened = not window_is_valid(view)
	if opened then
		view.win =
			vim.api.nvim_open_win(view.buf, true, floating_window_config(view.config, view.title, footer_text(view)))
		view.applied_window_options = {}
		apply_window_options(view)
	else
		vim.api.nvim_set_current_win(view.win)
		apply_window_config(view)
	end
	move_cursor_to_end(view)
	if not opened then
		return false, nil
	end
	return true, { buf = view.buf, win = view.win, reopened = reopened }
end

---@param view wiremux.ui.ComposeView
function M.hide(view)
	if not window_is_valid(view) then
		return
	end
	close_placeholder_preview(view)
	local win = view.win
	vim.api.nvim_win_close(win, true)
	if view.win == win then
		view.win = nil
	end
	view.applied_window_options = {}
end

---@param view wiremux.ui.ComposeView
---@param text string
---@param resume_insert boolean
function M.insert_at_cursor(view, text, resume_insert)
	if not buffer_is_valid(view) or not window_is_valid(view) then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(view.win)
	local row, col = cursor[1] - 1, cursor[2]
	vim.api.nvim_buf_set_text(view.buf, row, col, row, col, { text })
	vim.api.nvim_win_set_cursor(view.win, { row + 1, col + #text })
	if resume_insert then
		vim.cmd("startinsert")
	end
end

---@param view wiremux.ui.ComposeView
function M.move_cursor_to_end(view)
	move_cursor_to_end(view)
end

---@param view wiremux.ui.ComposeView
function M.close(view)
	release(view, true, false)
end

return M
