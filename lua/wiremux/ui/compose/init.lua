---@class wiremux.ui.ComposeState
---@field buf number
---@field win number?
---@field config wiremux.config.ComposeUIConfig
---@field on_confirm fun(text: string)
---@field on_cancel? fun()
---@field sent boolean

local normalize_keymap = require("wiremux.ui.compose.keymaps").normalize
local find_key_for_mode = require("wiremux.ui.compose.keymaps").find_key_for_mode

local M = {}

local _win = nil
local _buf = nil
local _state = nil

---@return number? buf The current compose draft buffer, if valid
function M.get_buf()
	if _buf and vim.api.nvim_buf_is_valid(_buf) then
		return _buf
	end
end

local function clamp(value, min_value, max_value)
	if value < min_value then
		return min_value
	end
	if value > max_value then
		return max_value
	end
	return value
end

local function create_buffer(text)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].filetype = "markdown"
	return buf
end

---@param buf number
---@param config wiremux.config.ComposeUIConfig
---@return number
local function create_window(buf, config)
	local width_ratio = tonumber(config.width) or 0.6
	local height_ratio = tonumber(config.height) or 0.4
	width_ratio = clamp(width_ratio, 0.1, 1)
	height_ratio = clamp(height_ratio, 0.1, 1)

	local min_width = math.min(20, vim.o.columns)
	local min_height = math.min(3, vim.o.lines)
	local width = clamp(math.floor(vim.o.columns * width_ratio), min_width, vim.o.columns)
	local height = clamp(math.floor(vim.o.lines * height_ratio), min_height, vim.o.lines)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = config.style,
		border = config.border,
		title = config.title,
		title_pos = "center",
	})

	for opt, val in pairs(config.wo or {}) do
		vim.wo[win][opt] = val
	end

	return win
end

local function setup_syntax(buf)
	vim.api.nvim_buf_call(buf, function()
		vim.cmd([[
			syntax match WiremuxPlaceholder /{[^}]\+}/
			highlight default link WiremuxPlaceholder Special
		]])
	end)
end

---@param buf number
---@return string
local function get_buffer_text(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, "\n")
end

---@param state wiremux.ui.ComposeState
---@return boolean
local function is_draft_empty(state)
	if not vim.api.nvim_buf_is_valid(state.buf) then
		return true
	end
	return get_buffer_text(state.buf):match("^%s*$") ~= nil
end

---@param buf number
---@param text string
local function set_buffer_text(buf, text)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
end

---@param win number
---@param buf number
local function move_cursor_to_end(win, buf)
	local last_row = vim.api.nvim_buf_line_count(buf)
	local last_line = vim.api.nvim_buf_get_lines(buf, last_row - 1, last_row, false)[1] or ""
	vim.api.nvim_win_set_cursor(win, { last_row, #last_line })
end

---@param state wiremux.ui.ComposeState
local function hide_window(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
end

---@param state wiremux.ui.ComposeState
local function discard_draft(state)
	hide_window(state)
	if vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
end

---@param state wiremux.ui.ComposeState
local function request_discard(state)
	if state.sent then
		return
	end

	discard_draft(state)
end

---@param state wiremux.ui.ComposeState
local function send(state)
	if state.sent then
		return
	end
	state.sent = true
	local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
	hide_window(state)
	if vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	vim.schedule(function()
		state.on_confirm(table.concat(lines, "\n"))
	end)
end

---@param state wiremux.ui.ComposeState
local function update_footer(state)
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end

	local is_insert = vim.fn.mode() == "i"
	local current_mode = is_insert and "i" or "n"
	local km = state.config.keymaps or {}

	local parts = {}
	local keys = {
		{ entry = km.send, label = "Send" },
		{ entry = km.close, label = "Close" },
		{ entry = km.discard, label = "Discard" },
		{ entry = km.files, label = "Files" },
	}
	for _, k in ipairs(keys) do
		local key = find_key_for_mode(k.entry, current_mode)
		if key then
			table.insert(parts, key .. " " .. k.label)
		end
	end

	if #parts == 0 then
		vim.api.nvim_win_set_config(state.win, { footer = nil })
		return
	end

	vim.api.nvim_win_set_config(state.win, {
		footer = " " .. table.concat(parts, "  |  ") .. " ",
		footer_pos = "center",
	})
end

---@param state wiremux.ui.ComposeState
local function insert_file(state)
	local picker = require("wiremux.picker")
	local was_insert = vim.fn.mode() == "i"
	picker.files({ prompt = "Insert file" }, function(path)
		if not path or not vim.api.nvim_buf_is_valid(state.buf) then
			return
		end
		vim.schedule(function()
			if not state.win or not vim.api.nvim_win_is_valid(state.win) then
				return
			end
			local cursor = vim.api.nvim_win_get_cursor(state.win)
			local row, col = cursor[1] - 1, cursor[2]
			vim.api.nvim_buf_set_text(state.buf, row, col, row, col, { path })
			vim.api.nvim_win_set_cursor(state.win, { row + 1, col + #path })
			if was_insert then
				vim.cmd("startinsert")
			end
		end)
	end)
end

---@param state wiremux.ui.ComposeState
local function request_close(state)
	if state.sent then
		return
	end

	if is_draft_empty(state) then
		discard_draft(state)
		return
	end

	local behavior = state.config.close_behavior or "ask"
	if behavior == "hide" then
		hide_window(state)
		return
	end

	if behavior == "discard" then
		request_discard(state)
		return
	end

	local choice = vim.fn.confirm("Unsent draft: what do you want to do?", "&Hide\n&Discard\n&Keep Editing", 3)

	if choice == 1 then
		hide_window(state)
		return
	end

	if choice == 2 then
		request_discard(state)
	end
end

---@param state wiremux.ui.ComposeState
local function setup_keymaps(state)
	local keymaps = state.config.keymaps or {}
	local actions = {
		send = function()
			send(state)
		end,
		close = function()
			request_close(state)
		end,
		discard = function()
			request_discard(state)
		end,
		files = function()
			insert_file(state)
		end,
	}

	for action, handler in pairs(actions) do
		for _, km in ipairs(normalize_keymap(keymaps[action])) do
			for _, mode in ipairs(km.modes) do
				vim.keymap.set(mode, km.key, handler, {
					buffer = state.buf,
					nowait = mode == "n",
					desc = km.desc or action,
				})
			end
		end
	end

	vim.keymap.set("n", "<C-o>", "<Nop>", { buffer = state.buf, nowait = true })
	vim.keymap.set("n", "<C-i>", "<Nop>", { buffer = state.buf, nowait = true })
end

---@param state wiremux.ui.ComposeState
local function setup_autocmds(state)
	local group = vim.api.nvim_create_augroup("wiremux_compose_" .. state.buf, { clear = true })

	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		buffer = state.buf,
		callback = function()
			update_footer(state)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = state.buf,
		callback = function()
			vim.api.nvim_del_augroup_by_id(group)
			_win = nil
			_buf = nil
			_state = nil
			if not state.sent and state.on_cancel then
				state.on_cancel()
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = "*",
		callback = function(args)
			local closed_win = tonumber(args.match)
			if state.win == closed_win then
				state.win = nil
				if _win == closed_win then
					_win = nil
				end
			end
		end,
	})
end

---@param state wiremux.ui.ComposeState
---@param text string
local function apply_new_payload_policy(state, text)
	local current_text = get_buffer_text(state.buf)
	if text == current_text then
		return
	end

	local policy = state.config.on_new_payload or "ask"
	if policy == "keep" then
		return
	end

	if policy == "replace" then
		set_buffer_text(state.buf, text)
		return
	end

	local choice =
		vim.fn.confirm("An unsent draft already exists. Which one should be used?", "&Keep Draft\n&Replace With New", 1)
	if choice == 2 then
		set_buffer_text(state.buf, text)
	end
end

---Open compose buffer for text modification
---@param text string Initial text (with unresolved placeholders)
---@param on_confirm fun(edited_text: string) Callback when user confirms
---@param on_cancel? fun() Optional callback when user cancels
function M.open(text, on_confirm, on_cancel)
	if _state and (not _state.buf or not vim.api.nvim_buf_is_valid(_state.buf)) then
		_state = nil
		_win = nil
		_buf = nil
	end

	local config = require("wiremux.config").opts.ui.compose

	if _state and not _state.sent and vim.api.nvim_buf_is_valid(_state.buf) then
		local state = _state
		state.config = config
		state.on_confirm = on_confirm
		state.on_cancel = on_cancel

		apply_new_payload_policy(state, text)

		if not state.win or not vim.api.nvim_win_is_valid(state.win) then
			state.win = create_window(state.buf, state.config)
			_win = state.win
		else
			vim.api.nvim_set_current_win(state.win)
		end

		update_footer(state)
		move_cursor_to_end(state.win, state.buf)
		return
	end

	---@type wiremux.ui.ComposeState
	local state = {
		buf = create_buffer(text),
		config = config,
		on_confirm = on_confirm,
		on_cancel = on_cancel,
		sent = false,
	}

	state.win = create_window(state.buf, config)

	setup_syntax(state.buf)
	setup_keymaps(state)
	update_footer(state)
	setup_autocmds(state)

	_win = state.win
	_buf = state.buf
	_state = state

	move_cursor_to_end(state.win, state.buf)
end

return M
