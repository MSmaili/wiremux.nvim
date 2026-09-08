---@module 'luassert'

local helpers = require("tests.helpers")

describe("resolver filtering", function()
	local resolver, config

	before_each(function()
		helpers.clear({
			"wiremux.core.resolver",
			"wiremux.config",
		})

		config = require("wiremux.config")

		resolver = require("wiremux.core.resolver")
	end)

	describe("instance filtering", function()
		it("scopes managed targets by origin rather than session and excludes the current pane", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%0", managed = true, session_id = "$1", target = "current", origin = "%0", kind = "pane" },
					{ id = "%1", managed = true, session_id = "$1", target = "ai", origin = "%0", kind = "pane" },
					{ id = "%2", managed = true, session_id = "$1", target = "test", origin = "%99", kind = "pane" },
					{ id = "%3", managed = true, session_id = "$2", target = "remote", origin = "%0", kind = "pane" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "all" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(2, #result.targets)
			assert.are.equal("%1", result.targets[1].id)
			assert.are.equal("%3", result.targets[2].id)
		end)

		it("shows all when no filter", function()
			config.opts.picker.instances.filter = nil

			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", target = "ai", origin = "%0", kind = "pane" },
					{ id = "%2", managed = true, session_id = "$1", target = "test", origin = "%99", kind = "pane" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "all" })

			assert.are.equal("targets", result.kind)
			assert.are.equal(2, #result.targets)
		end)

		it("applies custom filter", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", target = "ai", origin = "%0", kind = "pane" },
					{ id = "%2", managed = true, session_id = "$1", target = "test", origin = "%0", kind = "window" },
				},
			}

			local result = resolver.resolve(state, {}, {
				behavior = "all",
				filter = {
					instances = function(inst)
						return inst.kind == "pane"
					end,
				},
			})

			assert.are.equal("targets", result.kind)
			assert.are.equal(1, #result.targets)
			assert.are.equal("pane", result.targets[1].kind)
		end)

		it("action filter overrides global filter", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", target = "ai", origin = "%0", kind = "pane" },
					{ id = "%2", managed = true, session_id = "$1", target = "test", origin = "%99", kind = "pane" },
				},
			}

			local result = resolver.resolve(state, {}, {
				behavior = "all",
				filter = {
					instances = function()
						return true
					end,
				},
			})

			assert.are.equal("targets", result.kind)
			assert.are.equal(2, #result.targets)
		end)
	end)

	describe("definition filtering", function()
		it("applies no filter by default", function()
			local state = { origin_pane_id = "%0", session_id = "$1", instances = {} }
			local definitions = {
				ai = { cmd = "aichat" },
				test = { cmd = "pytest" },
			}

			local result = resolver.resolve(state, definitions, { behavior = "pick" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
		end)

		it("applies custom definition filter", function()
			local state = { origin_pane_id = "%0", session_id = "$1", instances = {} }
			local definitions = {
				ai = { cmd = "aichat" },
				test = { cmd = "pytest" },
			}

			local result = resolver.resolve(state, definitions, {
				behavior = "pick",
				filter = {
					definitions = function(name, def)
						return name ~= "test"
					end,
				},
			})

			assert.are.equal("pick", result.kind)
			assert.are.equal(1, #result.items)
			assert.are.equal("ai", result.items[1].target)
		end)
	end)

	describe("last_used with filtering", function()
		it("uses last_used if in filtered set", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				last_used_target_id = "%1",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", target = "ai", origin = "%0", kind = "pane" },
					{ id = "%2", managed = true, session_id = "$1", target = "test", origin = "%0", kind = "pane" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "last" })

			assert.are.equal("targets", result.kind)
			assert.are.equal("%1", result.targets[1].id)
		end)

		it("falls back when last_used filtered out", function()
			local state = {
				origin_pane_id = "%0",
				session_id = "$1",
				last_used_target_id = "%99",
				instances = {
					{ id = "%1", managed = true, session_id = "$1", target = "ai", origin = "%0", kind = "pane" },
					{ id = "%2", managed = true, session_id = "$1", target = "test", origin = "%0", kind = "pane" },
				},
			}

			local result = resolver.resolve(state, {}, { behavior = "last" })

			assert.are.equal("pick", result.kind)
			assert.are.equal(2, #result.items)
		end)
	end)
end)
