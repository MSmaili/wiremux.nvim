local M = {}

---@param args string[]
---@param accept_codes? number[] Additional exit codes to accept as success (besides 0)
---@return string? stdout, string? error
local function tmux_cmd(args, accept_codes)
	local cmd = vim.list_extend({ "tmux" }, args)
	local ok, result = pcall(function()
		return vim.system(cmd, { text = true }):wait()
	end)

	if not ok then
		return nil, "command failed"
	end

	-- Check if exit code is acceptable
	local code_ok = result.code == 0
	if not code_ok and accept_codes then
		code_ok = vim.tbl_contains(accept_codes, result.code)
	end

	if code_ok then
		return result.stdout and vim.trim(result.stdout) or "", nil
	end

	return nil, result.stderr or "command failed"
end

---@return string?
local function get_tmux_version()
	local stdout, _ = tmux_cmd({ "-V" })
	return stdout
end

---@param version_str string
---@return number? major
local function parse_version(version_str)
	local major = version_str:match("tmux%s+(%d+)")
	return major and tonumber(major) or nil
end

---@return table? config
---@return string? error
local function get_config()
	local ok, config = pcall(require, "wiremux.config")
	if not ok or not config.opts then
		return nil, "Configuration not initialized"
	end
	return config.opts, nil
end

local function check_tmux_environment()
	vim.health.start("Environment")

	if vim.env.TMUX then
		vim.health.ok("tmux environment detected: " .. vim.env.TMUX)
	else
		vim.health.error("Not running inside tmux session", "Start tmux first: `tmux new-session -s mysession`")
		return false
	end

	return true
end

local function check_tmux_executable()
	local version = get_tmux_version()
	if version then
		local major = parse_version(version)
		if major and major < 3 then
			vim.health.warn(
				"tmux " .. version .. " (some features may not work)",
				"Consider upgrading to tmux 3.0+ for full compatibility"
			)
		else
			vim.health.ok("tmux " .. version)
		end
	else
		vim.health.error(
			"tmux executable not found in PATH",
			"Install tmux: https://github.com/tmux/tmux/wiki/Installing"
		)
		return false
	end

	return true
end

local function check_tmux_socket()
	if not vim.env.TMUX then
		return
	end

	local socket_path = vim.env.TMUX:match("^([^,]+)")
	if socket_path then
		local stat = vim.uv.fs_stat(socket_path)
		if stat then
			vim.health.ok("TMUX socket accessible: " .. socket_path)
		else
			vim.health.error("TMUX socket not accessible: " .. socket_path, "Check file permissions or restart tmux")
		end
	end
end

local function check_config()
	vim.health.start("Configuration")

	local opts, err = get_config()
	if not opts then
		vim.health.warn(err or "Configuration not initialized", "Call require('wiremux').setup() in your config")
		return
	end

	-- Validate configuration values
	local validate = require("wiremux.utils.validate")
	local validation_errors = validate.validate(opts)

	if #validation_errors == 0 then
		vim.health.ok("All configuration values are valid")
	else
		for _, validation_err in ipairs(validation_errors) do
			vim.health.warn(validation_err)
		end
	end

	-- Check target definitions
	local definitions = vim.tbl_get(opts, "targets", "definitions") or {}
	local def_count = vim.tbl_count(definitions)

	if def_count > 0 then
		vim.health.ok(string.format("%d target definitions configured", def_count))
	else
		vim.health.warn("No target definitions configured", {
			"Add targets in your setup():",
			"",
			"    require('wiremux').setup({",
			"      targets = {",
			"        definitions = {",
			"          server = { cmd = 'npm run server' },",
			"          test = { cmd = 'npm test' },",
			"        }",
			"      }",
			"    })",
		})
	end
end

local function check_origin_pane()
	vim.health.start("Runtime")

	if not vim.env.TMUX then
		return
	end

	local pane_id, err = tmux_cmd({ "display-message", "-p", "#D" })
	if not err then
		vim.health.ok("Origin pane: " .. pane_id)
	else
		vim.health.error("Failed to detect origin pane")
	end
end

local function check_tmux_queries()
	if not vim.env.TMUX then
		return
	end

	local _, err = tmux_cmd({ "list-panes", "-F", "#D" })
	if not err then
		vim.health.ok("Can query tmux state")
	else
		vim.health.error("Cannot execute tmux commands")
	end
end

local function check_pane_metadata()
	if not vim.env.TMUX then
		return
	end

	-- Exit code 1 = option not set (expected for test option), so we accept it
	local _, err = tmux_cmd({ "show-options", "-p", "@wiremux_test" }, { 1 })
	if not err then
		vim.health.ok("Pane metadata accessible")
	else
		vim.health.warn("Cannot read pane metadata (tmux 3.0+ required)")
	end
end

local function check_optional_dependencies()
	vim.health.start("Optional Dependencies")

	local opts = get_config()
	local picker = require("wiremux.picker")

	-- Show configured picker
	if opts and opts.picker then
		if type(opts.picker) == "function" then
			vim.health.ok("Custom picker function configured")
		elseif type(opts.picker) == "string" then
			vim.health.info("Configured picker: " .. opts.picker)
		end
	end

	-- Check available adapters and show which will be used
	local available_adapters = {}
	for _, adapter_name in ipairs(picker.ADAPTERS) do
		local ok, adapter = pcall(require, "wiremux.picker." .. adapter_name)
		if ok and adapter.available and adapter.available() then
			table.insert(available_adapters, adapter_name)
		end
	end

	if #available_adapters > 0 then
		vim.health.info("Available adapters: " .. table.concat(available_adapters, ", "))

		-- Determine which picker will actually be used
		local active_picker = "vim.ui.select (built-in)"
		if opts and opts.picker then
			if type(opts.picker) == "function" then
				active_picker = "custom function"
			elseif type(opts.picker) == "string" then
				-- Check if configured picker is available
				local ok, adapter = pcall(require, "wiremux.picker." .. opts.picker)
				if ok and adapter.available and adapter.available() then
					active_picker = opts.picker
				else
					-- Will auto-detect from available adapters
					active_picker = available_adapters[1] .. " (auto-detected)"
				end
			end
		else
			-- No picker configured, will auto-detect
			active_picker = available_adapters[1] .. " (auto-detected)"
		end

		vim.health.ok("Active picker: " .. active_picker)
	else
		vim.health.ok("Using built-in vim.ui.select (no optional pickers available)")
	end
end

function M.check()
	vim.health.start("wiremux")

	local env_ok = check_tmux_environment()
	if env_ok then
		check_tmux_executable()
		check_tmux_socket()
	end

	check_config()

	if env_ok then
		check_origin_pane()
		check_tmux_queries()
		check_pane_metadata()
	end

	check_optional_dependencies()
end

return M
