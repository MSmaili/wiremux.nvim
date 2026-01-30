-- plugin/wiremux.lua - Auto-loaded on startup
-- Commands are defined here to enable lazy loading of the main plugin

if vim.g.loaded_wiremux then
	return
end
vim.g.loaded_wiremux = true

---@class wiremux.Subcommand
---@field impl fun(args: string[], opts: table): nil Command implementation
---@field complete? fun(arg_lead: string): string[] Optional completions
---@field desc string Command description

---@type table<string, wiremux.Subcommand>
local subcommand_tbl = {
	send = {
		impl = function(args, _)
			local text = table.concat(args, " ")
			require("wiremux.action.send").send(text)
		end,
		desc = "Send text to tmux target",
	},
	["send-motion"] = {
		impl = function(_, _)
			require("wiremux.action.send_motion").send_motion()
		end,
		desc = "Send motion/textobject to tmux target (operator pending)",
	},
	focus = {
		impl = function(_, _)
			require("wiremux.action.focus").focus()
		end,
		desc = "Focus tmux target",
	},
	create = {
		impl = function(_, _)
			require("wiremux.action.create").create()
		end,
		desc = "Create new tmux target from definitions",
	},
	close = {
		impl = function(_, _)
			require("wiremux.action.close").close()
		end,
		desc = "Close tmux target pane(s)/window(s)",
	},
	toggle = {
		impl = function(_, _)
			require("wiremux.action.toggle").toggle()
		end,
		desc = "Toggle between creating and focusing tmux targets",
	},
	health = {
		impl = function(_, _)
			vim.cmd("checkhealth wiremux")
		end,
		desc = "Run wiremux health check",
	},
}

---@param opts {fargs: string[]} Command options
local function wiremux_cmd(opts)
	local fargs = opts.fargs
	local subcommand_key = fargs[1]
	local args = #fargs > 1 and { unpack(fargs, 2, #fargs) } or {}
	local subcommand = subcommand_tbl[subcommand_key]
	if not subcommand then
		vim.notify("Wiremux: Unknown command: " .. (subcommand_key or "nil"), vim.log.levels.ERROR)
		return
	end

	local ok, err = pcall(subcommand.impl, args, opts)
	if not ok then
		vim.notify("Wiremux error: " .. tostring(err), vim.log.levels.ERROR)
	end
end

vim.api.nvim_create_user_command("Wiremux", wiremux_cmd, {
	nargs = "+",
	desc = "Wiremux tmux integration commands",
	complete = function(arg_lead, cmdline, _)
		-- Extract subcommand and its arguments (require at least one space)
		local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Wiremux[!]*%s+(%S+)%s+(.*)$")

		-- Return subcommand's completions if available
		if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
			return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
		end

		-- Return list of subcommands (prefix match, sorted)
		if cmdline:match("^['<,'>]*Wiremux[!]*%s+%w*$") then
			local subcommand_keys = vim.tbl_keys(subcommand_tbl)
			table.sort(subcommand_keys)
			return vim.iter(subcommand_keys)
				:filter(function(key)
					return vim.startswith(key, arg_lead)
				end)
				:totable()
		end
	end,
})
