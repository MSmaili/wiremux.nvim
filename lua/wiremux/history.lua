local M = {}

local INDEX_VERSION = 1
local DIRECTORY_MODE = 448 -- 0700
local FILE_MODE = 384 -- 0600

---@class wiremux.history.Entry
---@field created_at number
---@field preview string
---@field size number
---@field file string

---@class wiremux.history.Index
---@field version integer
---@field entries wiremux.history.Entry[]

local function paths()
	local root = vim.fs.joinpath(vim.fn.stdpath("state"), "wiremux", "history")
	return {
		root = root,
		index = vim.fs.joinpath(root, "index.json"),
	}
end

local function missing(code, err)
	return code == "ENOENT" or (type(err) == "string" and err:match("ENOENT")) ~= nil
end

---@return table? resolved_paths
---@return string? error
local function ensure_root()
	local resolved = paths()
	local ok, mkdir_err = pcall(vim.fn.mkdir, resolved.root, "p", DIRECTORY_MODE)
	if not ok then
		return nil, tostring(mkdir_err)
	end
	local stat, stat_err = vim.uv.fs_stat(resolved.root)
	if not stat then
		return nil, tostring(stat_err or "failed to create history directory")
	end
	if stat.type ~= "directory" then
		return nil, resolved.root .. " is not a directory"
	end
	local secured, chmod_err = vim.uv.fs_chmod(resolved.root, DIRECTORY_MODE)
	if not secured then
		return nil, tostring(chmod_err)
	end
	return resolved, nil
end

---@param path string
---@return string? data
---@return string? error
local function read_file(path)
	local fd, open_err = vim.uv.fs_open(path, "r", FILE_MODE)
	if not fd then
		return nil, tostring(open_err)
	end
	local stat, stat_err = vim.uv.fs_fstat(fd)
	if not stat then
		vim.uv.fs_close(fd)
		return nil, tostring(stat_err)
	end
	local data, read_err = "", nil
	if stat.size > 0 then
		data, read_err = vim.uv.fs_read(fd, stat.size, 0)
	end
	vim.uv.fs_close(fd)
	if data == nil then
		return nil, tostring(read_err)
	end
	return data, nil
end

local function token()
	local ticks = tostring(vim.uv.hrtime()):gsub("%D", "")
	return string.format("%d-%d-%s", os.time(), vim.uv.os_getpid(), ticks)
end

---@param path string
---@param data string
---@return boolean
---@return string? error
local function atomic_write(path, data)
	local fd, temporary_or_err = vim.uv.fs_mkstemp(path .. ".tmp-XXXXXX")
	if not fd then
		return false, tostring(temporary_or_err)
	end
	local temporary = temporary_or_err
	local secured, chmod_err = vim.uv.fs_chmod(temporary, FILE_MODE)
	if not secured then
		vim.uv.fs_close(fd)
		vim.uv.fs_unlink(temporary)
		return false, tostring(chmod_err)
	end

	local offset = 0
	local write_err
	while offset < #data do
		local written
		written, write_err = vim.uv.fs_write(fd, data:sub(offset + 1), offset)
		if not written or written == 0 then
			break
		end
		offset = offset + written
	end
	local closed, close_err = vim.uv.fs_close(fd)
	if offset ~= #data or not closed then
		vim.uv.fs_unlink(temporary)
		return false, tostring(write_err or close_err or "short write")
	end

	local renamed, rename_err = vim.uv.fs_rename(temporary, path)
	if not renamed then
		vim.uv.fs_unlink(temporary)
		return false, tostring(rename_err)
	end
	return true, nil
end

---@param value any
---@return boolean
local function valid_entry(value)
	return type(value) == "table"
		and type(value.created_at) == "number"
		and type(value.preview) == "string"
		and type(value.size) == "number"
		and value.size >= 0
		and value.size % 1 == 0
		and type(value.file) == "string"
		and value.file:match("^[%w_-]+%.txt$") ~= nil
end

---@param value any
---@return boolean
local function valid_index(value)
	if type(value) ~= "table" or value.version ~= INDEX_VERSION or not vim.islist(value.entries) then
		return false
	end
	for _, entry in ipairs(value.entries) do
		if not valid_entry(entry) then
			return false
		end
	end
	return true
end

---@param resolved table
---@return wiremux.history.Index? index
---@return string? error
local function load_index(resolved)
	local stat, stat_err, stat_code = vim.uv.fs_lstat(resolved.index)
	if not stat then
		if missing(stat_code, stat_err) then
			return { version = INDEX_VERSION, entries = {} }, nil
		end
		return nil, tostring(stat_err)
	end
	if stat.type ~= "file" then
		return nil, "history index is not a regular file"
	end

	local data, read_err = read_file(resolved.index)
	if data == nil then
		return nil, read_err
	end
	local ok, decoded = pcall(vim.json.decode, data)
	if not ok or not valid_index(decoded) then
		return nil, "history index is malformed"
	end
	return decoded, nil
end

---@param resolved table
---@param index wiremux.history.Index
---@return boolean
---@return string? error
local function write_index(resolved, index)
	local ok, encoded = pcall(vim.json.encode, index)
	if not ok then
		return false, tostring(encoded)
	end
	return atomic_write(resolved.index, encoded)
end

---@param payload string
---@return string
local function preview(payload)
	for line in (payload .. "\n"):gmatch("(.-)\n") do
		if line:match("%S") then
			local text = vim.trim(line):gsub("%s+", " ")
			if vim.fn.strchars(text) > 80 then
				return vim.fn.strcharpart(text, 0, 80) .. "…"
			end
			return text
		end
	end
	return "(empty)"
end

---@param resolved table
---@param entries wiremux.history.Entry[]
---@param limit integer
---@return wiremux.history.Entry[] entries
---@return boolean changed
local function reconcile(resolved, entries, limit)
	local kept = {}
	local changed = false
	for _, entry in ipairs(entries) do
		local stat = vim.uv.fs_lstat(vim.fs.joinpath(resolved.root, entry.file))
		if stat and stat.type == "file" and #kept < limit then
			table.insert(kept, entry)
		else
			changed = true
		end
	end
	return kept, changed
end

---@param resolved table
---@param entries wiremux.history.Entry[]
---@return boolean
---@return string? error
local function cleanup(resolved, entries)
	local keep = { ["index.json"] = true }
	for _, entry in ipairs(entries) do
		keep[entry.file] = true
	end

	local scan, scan_err = vim.uv.fs_scandir(resolved.root)
	if not scan then
		return false, tostring(scan_err)
	end
	while true do
		local name, entry_type = vim.uv.fs_scandir_next(scan)
		if not name then
			break
		end
		if entry_type ~= "directory" and not keep[name] and (name:match("%.txt$") or name:match("%.tmp%-")) then
			local removed, remove_err = vim.uv.fs_unlink(vim.fs.joinpath(resolved.root, name))
			if not removed then
				return false, tostring(remove_err)
			end
		end
	end
	return true, nil
end

local function history_limit()
	return require("wiremux.config").get().ui.compose.history_limit
end

---List history metadata without reading payload files.
---@return wiremux.history.Entry[]? entries
---@return string? cleanup_error
function M.list()
	local limit = history_limit()
	local resolved = paths()
	local root_stat, root_err, root_code = vim.uv.fs_stat(resolved.root)
	if not root_stat then
		if missing(root_code, root_err) then
			return {}, nil
		end
		return nil, tostring(root_err)
	end
	if root_stat.type ~= "directory" then
		return nil, resolved.root .. " is not a directory"
	end

	local index, load_err = load_index(resolved)
	if not index then
		return nil, load_err
	end
	local entries, changed = reconcile(resolved, index.entries, limit)
	if changed then
		local written, write_err = write_index(resolved, { version = INDEX_VERSION, entries = entries })
		if not written then
			return nil, write_err
		end
	end
	local cleaned, cleanup_err = cleanup(resolved, entries)
	return entries, cleaned and nil or cleanup_err
end

---Store one resolved compose payload.
---@param payload string
---@return boolean
---@return string? cleanup_error
function M.add(payload)
	if type(payload) ~= "string" then
		return false, "history payload must be a string"
	end
	local limit = history_limit()
	if limit == 0 then
		local entries, list_err = M.list()
		return entries ~= nil, list_err
	end

	local resolved, root_err = ensure_root()
	if not resolved then
		return false, root_err
	end
	local index, load_err = load_index(resolved)
	if not index then
		return false, load_err
	end
	local entries = reconcile(resolved, index.entries, math.max(limit - 1, 0))

	local entry = {
		created_at = os.time(),
		preview = preview(payload),
		size = #payload,
		file = token() .. ".txt",
	}
	local payload_path = vim.fs.joinpath(resolved.root, entry.file)
	local written, write_err = atomic_write(payload_path, payload)
	if not written then
		return false, write_err
	end

	table.insert(entries, 1, entry)
	written, write_err = write_index(resolved, { version = INDEX_VERSION, entries = entries })
	if not written then
		return false, write_err
	end
	local cleaned, cleanup_err = cleanup(resolved, entries)
	return true, cleaned and nil or cleanup_err
end

---Resolve one entry to its payload path without reading it.
---@param entry wiremux.history.Entry
---@return string? path
---@return string? error
function M.path(entry)
	if not valid_entry(entry) then
		return nil, "history entry is malformed"
	end
	return vim.fs.joinpath(paths().root, entry.file), nil
end

---Load one selected payload.
---@param entry wiremux.history.Entry
---@return string? payload
---@return string? error
function M.read(entry)
	local path, path_err = M.path(entry)
	if not path then
		return nil, path_err
	end
	local stat, stat_err = vim.uv.fs_lstat(path)
	if not stat or stat.type ~= "file" then
		return nil, stat_err and tostring(stat_err) or "history payload is missing"
	end
	return read_file(path)
end

return M
