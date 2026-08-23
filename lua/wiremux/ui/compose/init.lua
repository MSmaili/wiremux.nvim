local draft_model = require("wiremux.ui.compose.draft")
local notify = require("wiremux.utils.notify")
local view = require("wiremux.ui.compose.view")

local M = {}

---@class wiremux.ui.ComposeOpenOptions
---@field on_confirm fun(pages: wiremux.ui.ComposePage[]): boolean?
---@field on_preview? fun(capture: any, name: string): string?, string?
---@field on_cancel? fun()
---@field capture? any
---@field config wiremux.config.ComposeSessionConfig Resolved session configuration

---@alias wiremux.ui.ComposeLifecycle "editing"|"confirming"|"sent"|"cancelled"

---@class wiremux.ui.ComposeSession
---@field view? wiremux.ui.ComposeView
---@field config? wiremux.config.ComposeSessionConfig
---@field title? string
---@field draft wiremux.ui.ComposeDraft
---@field on_confirm? fun(pages: wiremux.ui.ComposePage[]): boolean?
---@field on_preview? fun(capture: any, name: string): string?, string?
---@field on_cancel? fun()
---@field status wiremux.ui.ComposeLifecycle

---@type wiremux.ui.ComposeSession?
local active_session

---@return number? buf The current compose draft buffer, if valid
function M.get_buf()
	if active_session and active_session.view then
		return view.get_buf(active_session.view)
	end
end

---@param session wiremux.ui.ComposeSession
---@return string
local function window_title(session)
	local title = session.title or " Compose Message "
	if #session.draft.pages == 1 then
		return title
	end
	return string.format(
		"%s [%d/%d] ",
		title:gsub("%s+$", ""),
		session.draft.current_page,
		#session.draft.pages
	)
end

---@param session wiremux.ui.ComposeSession
local function save_current_page(session)
	if not session.view then
		return
	end
	local text = view.read_text(session.view)
	if text ~= nil and #session.draft.pages > 0 then
		draft_model.save(session.draft, text)
	end
end

---@param session wiremux.ui.ComposeSession
---@param status "sent"|"cancelled"
local function finalize_session(session, status)
	if session.status == "sent" or session.status == "cancelled" then
		return
	end

	local on_cancel = status == "cancelled" and session.on_cancel or nil
	local session_view = session.view
	session.status = status
	if active_session == session then
		active_session = nil
	end
	session.view = nil
	session.config = nil
	session.title = nil
	session.on_confirm = nil
	session.on_preview = nil
	session.on_cancel = nil
	session.draft.pages = {}
	session.draft.current_page = 1
	if session_view then
		view.close(session_view)
	end

	if on_cancel then
		local ok, err = pcall(on_cancel)
		if not ok then
			notify.error("wiremux compose cancellation failed: " .. tostring(err))
		end
	end
end

---@param session wiremux.ui.ComposeSession
local function on_view_wipeout(session)
	finalize_session(session, "cancelled")
end

---@param session wiremux.ui.ComposeSession
---@param reopened boolean
local function show_session(session, reopened)
	if session.status ~= "editing" or not session.view then
		return
	end
	view.set_title(session.view, window_title(session))
	local opened, event_data = view.show(session.view, reopened)
	if not opened or not event_data then
		return
	end

	local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "WiremuxComposeOpen",
		modeline = false,
		data = event_data,
	})
	if not ok then
		notify.error("WiremuxComposeOpen failed: " .. tostring(err))
	end
end

---@param session wiremux.ui.ComposeSession
local function hide_session(session)
	if session.status ~= "editing" or not session.view then
		return
	end
	save_current_page(session)
	view.hide(session.view)
end

---@param session wiremux.ui.ComposeSession
local function request_discard(session)
	if session.status == "editing" then
		finalize_session(session, "cancelled")
	end
end

---@param session wiremux.ui.ComposeSession
local function confirm_draft(session)
	if session.status ~= "editing" or not session.on_confirm then
		return
	end

	save_current_page(session)
	session.status = "confirming"
	local ok, confirmed = pcall(session.on_confirm, session.draft.pages)
	if session.status ~= "confirming" then
		return
	end
	if not ok then
		session.status = "editing"
		notify.error(tostring(confirmed))
		return
	end
	if confirmed == false then
		session.status = "editing"
		return
	end

	finalize_session(session, "sent")
end

---@param session wiremux.ui.ComposeSession
local function insert_file(session)
	if session.status ~= "editing" or not session.view then
		return
	end
	local originating_view = session.view
	local was_insert = vim.fn.mode() == "i"
	require("wiremux.picker").files({ prompt = "Insert file" }, function(path)
		if not path or active_session ~= session or session.status ~= "editing" or session.view ~= originating_view then
			return
		end
		vim.schedule(function()
			if active_session ~= session
				or session.status ~= "editing"
				or session.view ~= originating_view
				or not view.is_visible(originating_view)
			then
				return
			end
			view.insert_at_cursor(originating_view, path, was_insert)
		end)
	end)
end

---@param session wiremux.ui.ComposeSession
local function preview_placeholder(session)
	if session.status ~= "editing" or not session.view or not session.on_preview then
		return
	end
	if view.focus_placeholder_preview(session.view) then
		return
	end
	local name = view.placeholder_at_cursor(session.view)
	if name == nil then
		return
	end
	local ok, text, syntax = pcall(session.on_preview, draft_model.current(session.draft).capture, name)
	if not ok then
		notify.error("wiremux placeholder preview failed: " .. tostring(text))
		return
	end
	if text then
		view.show_placeholder_preview(session.view, text, syntax or "text")
	end
end

---@param session wiremux.ui.ComposeSession
---@param direction "previous"|"next"
local function navigate(session, direction)
	if session.status ~= "editing" or #session.draft.pages == 1 or not session.view then
		return
	end
	save_current_page(session)
	draft_model[direction](session.draft)
	view.load_text(session.view, draft_model.current(session.draft).text)
	view.set_title(session.view, window_title(session))
	view.move_cursor_to_end(session.view)
end

---@param session wiremux.ui.ComposeSession
local function delete_page(session)
	if session.status ~= "editing" or not session.view then
		return
	end
	draft_model.delete_current(session.draft)
	view.load_text(session.view, draft_model.current(session.draft).text)
	view.set_title(session.view, window_title(session))
	view.move_cursor_to_end(session.view)
end

---@param session wiremux.ui.ComposeSession
local function request_close(session)
	if session.status ~= "editing" then
		return
	end

	save_current_page(session)
	if draft_model.is_empty(session.draft) then
		finalize_session(session, "cancelled")
		return
	end

	local config = session.config or {}
	local behavior = config.close_behavior or "ask"
	if behavior == "hide" then
		hide_session(session)
	elseif behavior == "discard" then
		request_discard(session)
	else
		local choice = vim.fn.confirm("Unsent draft: what do you want to do?", "&Hide\n&Discard\n&Keep Editing", 3)
		if choice == 1 then
			hide_session(session)
		elseif choice == 2 then
			request_discard(session)
		end
	end
end

---@param session wiremux.ui.ComposeSession
---@return table<string, function>
local function session_handlers(session)
	return {
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
		delete_page = function()
			delete_page(session)
		end,
		preview_placeholder = function()
			preview_placeholder(session)
		end,
		previous = function()
			navigate(session, "previous")
		end,
		next = function()
			navigate(session, "next")
		end,
	}
end

---@param session wiremux.ui.ComposeSession
local function refresh_view(session)
	if not session.view or not session.config then
		return
	end
	view.reconfigure(session.view, session.config)
	view.install_keymaps(session.view, session_handlers(session))
	view.set_title(session.view, window_title(session))
end

---@param session wiremux.ui.ComposeSession
---@param text string
---@param capture? any
local function apply_new_payload_policy(session, text, capture)
	save_current_page(session)
	if draft_model.is_empty(session.draft) then
		draft_model.replace(session.draft, text, capture)
		if session.view then
			view.load_text(session.view, text)
		end
		return
	end

	local config = session.config or {}
	local policy = config.on_new_payload or "ask"
	if policy == "ask" then
		local choice = vim.fn.confirm(
			"An unsent draft already exists. What should happen to the new payload?",
			"&Keep Draft\n&Replace With New\n&Append",
			1
		)
		policy = choice == 2 and "replace" or choice == 3 and "append" or "keep"
	end

	if policy == "replace" then
		draft_model.replace(session.draft, text, capture)
		if session.view then
			view.load_text(session.view, text)
		end
	elseif policy == "append" then
		draft_model.append(session.draft, text, capture)
		if session.view then
			view.load_text(session.view, text)
		end
	end
end

---@param session wiremux.ui.ComposeSession
---@param config wiremux.config.ComposeSessionConfig
---@param opts wiremux.ui.ComposeOpenOptions
local function refresh_session(session, config, opts)
	session.config = config
	session.title = config.title or " Compose Message "
	session.on_confirm = opts.on_confirm
	session.on_preview = opts.on_preview
	session.on_cancel = opts.on_cancel
	refresh_view(session)
end

---@param text string
---@param config wiremux.config.ComposeSessionConfig
---@param opts wiremux.ui.ComposeOpenOptions
---@return wiremux.ui.ComposeSession
local function create_session(text, config, opts)
	---@type wiremux.ui.ComposeSession
	local session = {
		view = nil,
		config = config,
		title = config.title or " Compose Message ",
		draft = draft_model.new(text, opts.capture),
		on_confirm = opts.on_confirm,
		on_preview = opts.on_preview,
		on_cancel = opts.on_cancel,
		status = "editing",
	}
	session.view = view.new(text, config, {
		on_wipeout = function()
			on_view_wipeout(session)
		end,
	})
	view.install_keymaps(session.view, session_handlers(session))
	view.set_title(session.view, window_title(session))
	return session
end

---Open a compose draft with raw template text and an opaque page capture.
---@param text string
---@param opts? wiremux.ui.ComposeOpenOptions
function M.open(text, opts)
	opts = opts or {}
	assert(type(text) == "string", "wiremux compose text must be a string")

	if active_session and (not active_session.view or view.get_buf(active_session.view) == nil) then
		finalize_session(active_session, "cancelled")
	end

	if active_session and active_session.status == "editing" and text == "" then
		show_session(active_session, true)
		return
	end
	if active_session and active_session.status == "confirming" then
		return
	end

	assert(type(opts.on_confirm) == "function", "wiremux compose requires on_confirm")
	assert(type(opts.config) == "table", "wiremux compose requires a complete session config")
	local config = vim.deepcopy(opts.config)
	if active_session and active_session.status == "editing" then
		local session = active_session
		refresh_session(session, config, opts)
		apply_new_payload_policy(session, text, opts.capture)
		if session.view then
			view.set_title(session.view, window_title(session))
		end
		show_session(session, true)
		return
	end

	local session = create_session(text, config, opts)
	active_session = session
	show_session(session, false)
end

return M
