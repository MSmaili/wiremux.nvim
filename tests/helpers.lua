local M = {}

function M.clear(modules)
	for _, mod in ipairs(modules) do
		package.loaded[mod] = nil
	end
end

function M.register(map)
	for name, mock in pairs(map) do
		package.loaded[name] = mock
	end
end

function M.mock_backend(extra)
	local mock = {
		state = {
			get = function()
				return { instances = {}, last_used_target_id = nil }
			end,
		},
		create = function(name, def, state)
			return { id = "%1", kind = "pane", target = name }
		end,
		wait_for_ready = function(inst, opts, callback)
			callback()
		end,
	}
	if extra then
		for k, v in pairs(extra) do
			mock[k] = v
		end
	end
	return mock
end

function M.mock_config(actions)
	return {
		opts = {
			targets = { definitions = {} },
			actions = actions or {},
		},
	}
end

function M.mock_picker()
	return { select = function() end }
end

function M.mock_notify()
	return {
		warn = function() end,
		error = function() end,
		debug = function() end,
	}
end

function M.mock_resolver()
	return {
		resolve = function()
			return { kind = "targets", targets = {} }
		end,
	}
end

return M
