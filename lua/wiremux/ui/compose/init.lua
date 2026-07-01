local draft_model = require("wiremux.ui.compose.draft")
local normalize_keymap = require("wiremux.ui.compose.keymaps").normalize
local find_key_for_mode = require("wiremux.ui.compose.keymaps").find_key_for_mode
local notify = require("wiremux.utils.notify")

local M = {}

---@class wiremux.ui.ComposeOpenOptions
---@field on_confirm fun(pages: wiremux.ui.ComposePage[]): boolean?
---@field on_cancel? fun()
---@field page_meta? any
---@field title? string

---@class wiremux.ui.ComposeSession
---@field buf number
---@field win number?
---@field config wiremux.config.ComposeUIConfig
---@field title string
---@field draft wiremux.ui.ComposeDraft
---@field on_confirm fun(pages: wiremux.ui.ComposePage[]): boolean?
---@field on_cancel? fun()
---@field confirming boolean
---@field sent boolean
---@field cancelled boolean

---@type wiremux.ui.ComposeSession?
local active_session

---@return number? buf The current compose draft buffer, if valid
function M.get_buf()
	if active_session and vim.api.nvim_buf_is_valid(active_session.buf) then
		return active_session.buf
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

---@param session wiremux.ui.ComposeSession
---@return string
local function window_title(session)
	if #session.draft.pages == 1 then
		return session.title
	end
	return string.format(
		"%s [%d/%d] ",
		session.title:gsub("%s+$", ""),
		session.draft.current_page,
		#session.draft.pages
	)
end

---@param buf number
---@param config wiremux.config.ComposeUIConfig
---@param title string
---@return number
local function create_window(buf, config, title)
	local width_ratio = clamp(tonumber(config.width) or 0.6, 0.1, 1)
	local height_ratio = clamp(tonumber(config.height) or 0.4, 0.1, 1)
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
		title = title,
		title_pos = "center",
	})

	for opt, val in pairs(config.wo or {}) do
		vim.wo[win][opt] = val
	end
	return win
end

---@param text string
---@return number
local function create_buffer(text)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].filetype = "markdown"
	return buf
end

---@param buf number
---@return string
local function get_buffer_text(buf)
	return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

---@param buf number
---@param text string
local function load_buffer_text(buf, text)
	local undolevels = vim.bo[buf].undolevels
	vim.bo[buf].undolevels = -1
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
	vim.bo[buf].undolevels = undolevels
end

---@param session wiremux.ui.ComposeSession
local function save_current_page(session)
	if vim.api.nvim_buf_is_valid(session.buf) then
		draft_model.save(session.draft, get_buffer_text(session.buf))
	end
end

---@param session wiremux.ui.ComposeSession
local function update_title(session)
	if session.win and vim.api.nvim_win_is_valid(session.win) then
		vim.api.nvim_win_set_config(session.win, { title = window_title(session), title_pos = "center" })
	end
end

---@param win number
---@param buf number
local function move_cursor_to_end(win, buf)
	local last_row = vim.api.nvim_buf_line_count(buf)
	local last_line = vim.api.nvim_buf_get_lines(buf, last_row - 1, last_row, false)[1] or ""
	vim.api.nvim_win_set_cursor(win, { last_row, #last_line })
end

---@param session wiremux.ui.ComposeSession
local function hide_window(session)
	save_current_page(session)
	if session.win and vim.api.nvim_win_is_valid(session.win) then
		vim.api.nvim_win_close(session.win, true)
	end
	session.win = nil
end

---@param session wiremux.ui.ComposeSession
local function discard_draft(session)
	hide_window(session)
	if vim.api.nvim_buf_is_valid(session.buf) then
		vim.api.nvim_buf_delete(session.buf, { force = true })
	elseif active_session == session then
		active_session = nil
	end
end

---@param session wiremux.ui.ComposeSession
local function request_discard(session)
	if not session.sent and not session.confirming then
		discard_draft(session)
	end
end

---@param session wiremux.ui.ComposeSession
local function confirm_draft(session)
	if session.sent or session.confirming then
		return
	end

	save_current_page(session)
	session.confirming = true
	local ok, confirmed = pcall(session.on_confirm, session.draft.pages)
	if not ok then
		session.confirming = false
		notify.error(tostring(confirmed))
		return
	end
	if confirmed == false then
		session.confirming = false
		return
	end

	session.sent = true
	hide_window(session)
	if vim.api.nvim_buf_is_valid(session.buf) then
		vim.api.nvim_buf_delete(session.buf, { force = true })
	end
end

---@param session wiremux.ui.ComposeSession
local function update_footer(session)
	if not session.win or not vim.api.nvim_win_is_valid(session.win) then
		return
	end

	local current_mode = vim.fn.mode() == "i" and "i" or "n"
	local km = session.config.keymaps or {}
	local parts = {}
	local keys = {
		{ entry = km.send, label = "Send" },
		{ entry = km.close, label = "Close" },
		{ entry = km.discard, label = "Discard" },
		{ entry = km.files, label = "Files" },
	}
	for _, keymap in ipairs(keys) do
		local key = find_key_for_mode(keymap.entry, current_mode)
		if key then
			table.insert(parts, key .. " " .. keymap.label)
		end
	end

	vim.api.nvim_win_set_config(session.win, {
		footer = #parts > 0 and (" " .. table.concat(parts, "  |  ") .. " ") or nil,
		footer_pos = "center",
	})
end

---@param session wiremux.ui.ComposeSession
local function insert_file(session)
	local picker = require("wiremux.picker")
	local was_insert = vim.fn.mode() == "i"
	picker.files({ prompt = "Insert file" }, function(path)
		if not path or not vim.api.nvim_buf_is_valid(session.buf) then
			return
		end
		vim.schedule(function()
			if not session.win or not vim.api.nvim_win_is_valid(session.win) then
				return
			end
			local cursor = vim.api.nvim_win_get_cursor(session.win)
			local row, col = cursor[1] - 1, cursor[2]
			vim.api.nvim_buf_set_text(session.buf, row, col, row, col, { path })
			vim.api.nvim_win_set_cursor(session.win, { row + 1, col + #path })
			if was_insert then
				vim.cmd("startinsert")
			end
		end)
	end)
end

---@param session wiremux.ui.ComposeSession
---@param direction "previous"|"next"
local function navigate(session, direction)
	if #session.draft.pages == 1 then
		return
	end
	save_current_page(session)
	draft_model[direction](session.draft)
	load_buffer_text(session.buf, draft_model.current(session.draft).text)
	update_title(session)
	if session.win and vim.api.nvim_win_is_valid(session.win) then
		move_cursor_to_end(session.win, session.buf)
	end
end

---@param session wiremux.ui.ComposeSession
local function request_close(session)
	if session.sent or session.confirming then
		return
	end

	save_current_page(session)
	if draft_model.is_empty(session.draft) then
		discard_draft(session)
		return
	end

	local behavior = session.config.close_behavior or "ask"
	if behavior == "hide" then
		hide_window(session)
	elseif behavior == "discard" then
		request_discard(session)
	else
		local choice = vim.fn.confirm("Unsent draft: what do you want to do?", "&Hide\n&Discard\n&Keep Editing", 3)
		if choice == 1 then
			hide_window(session)
		elseif choice == 2 then
			request_discard(session)
		end
	end
end

---@param session wiremux.ui.ComposeSession
local function setup_keymaps(session)
	local actions = {
		send = function()
			confirm_draft(session)
		end,
		close = function()
			request_close(session)
		end,
		discard = function()
			request_discard(session)
		end,
		files = function()
			insert_file(session)
		end,
		previous = function()
			navigate(session, "previous")
		end,
		next = function()
			navigate(session, "next")
		end,
	}

	for action, handler in pairs(actions) do
		for _, keymap in ipairs(normalize_keymap((session.config.keymaps or {})[action])) do
			for _, mode in ipairs(keymap.modes) do
				vim.keymap.set(mode, keymap.key, handler, {
					buffer = session.buf,
					nowait = mode == "n",
					desc = keymap.desc or action,
				})
			end
		end
	end

	vim.keymap.set("n", "<C-o>", "<Nop>", { buffer = session.buf, nowait = true })
	vim.keymap.set("n", "<C-i>", "<Nop>", { buffer = session.buf, nowait = true })
end

---@param session wiremux.ui.ComposeSession
local function setup_syntax(session)
	vim.api.nvim_buf_call(session.buf, function()
		vim.cmd([[
			syntax match WiremuxPlaceholder /{[^}]\+}/
			highlight default link WiremuxPlaceholder Special
		]])
	end)
end

---@param session wiremux.ui.ComposeSession
local function setup_autocmds(session)
	local group = vim.api.nvim_create_augroup("wiremux_compose_" .. session.buf, { clear = true })

	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		buffer = session.buf,
		callback = function()
			update_footer(session)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = session.buf,
		callback = function()
			pcall(vim.api.nvim_del_augroup_by_id, group)
			if active_session == session then
				active_session = nil
			end
			session.win = nil
			session.draft.pages = {}
			if not session.sent and not session.cancelled and session.on_cancel then
				session.cancelled = true
				session.on_cancel()
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = "*",
		callback = function(args)
			if session.win == tonumber(args.match) then
				session.win = nil
			end
		end,
	})
end

---@param session wiremux.ui.ComposeSession
local function show_session(session)
	if not session.win or not vim.api.nvim_win_is_valid(session.win) then
		session.win = create_window(session.buf, session.config, window_title(session))
	else
		vim.api.nvim_set_current_win(session.win)
	end
	update_title(session)
	update_footer(session)
	move_cursor_to_end(session.win, session.buf)
end

---@param session wiremux.ui.ComposeSession
---@param text string
---@param meta? any
local function apply_new_payload_policy(session, text, meta)
	save_current_page(session)
	if draft_model.is_empty(session.draft) then
		draft_model.replace(session.draft, text, meta)
		load_buffer_text(session.buf, text)
		return
	end

	local policy = session.config.on_new_payload or "ask"
	if policy == "ask" then
		local choice = vim.fn.confirm(
			"An unsent draft already exists. What should happen to the new payload?",
			"&Keep Draft\n&Replace With New\n&Append",
			1
		)
		policy = choice == 2 and "replace" or choice == 3 and "append" or "keep"
	end

	if policy == "replace" then
		draft_model.replace(session.draft, text, meta)
		load_buffer_text(session.buf, text)
	elseif policy == "append" then
		draft_model.append(session.draft, text, meta)
		load_buffer_text(session.buf, text)
	end
end

---Open a compose draft with unresolved text.
---@param text string
---@param opts wiremux.ui.ComposeOpenOptions
function M.open(text, opts)
	opts = opts or {}
	assert(type(opts.on_confirm) == "function", "wiremux compose requires on_confirm")

	if active_session and not vim.api.nvim_buf_is_valid(active_session.buf) then
		active_session = nil
	end

	local config = require("wiremux.config").opts.ui.compose
	if active_session and not active_session.sent then
		local session = active_session
		if text ~= "" then
			session.config = config
			session.title = opts.title or config.title or " Compose Message "
			session.on_confirm = opts.on_confirm
			session.on_cancel = opts.on_cancel
			apply_new_payload_policy(session, text, opts.page_meta)
		end
		show_session(session)
		return
	end

	---@type wiremux.ui.ComposeSession
	local session = {
		buf = create_buffer(text),
		config = config,
		title = opts.title or config.title or " Compose Message ",
		draft = draft_model.new(text, opts.page_meta),
		on_confirm = opts.on_confirm,
		on_cancel = opts.on_cancel,
		confirming = false,
		sent = false,
		cancelled = false,
	}
	active_session = session
	setup_syntax(session)
	setup_keymaps(session)
	setup_autocmds(session)
	show_session(session)
end

return M
