#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
vim.env.LAZY_PATH = vim.fs.normalize("~/projects/lazy.nvim")

if vim.fn.isdirectory(vim.env.LAZY_PATH) == 1 then
	loadfile(vim.env.LAZY_PATH .. "/bootstrap.lua")()
else
	load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"), "bootstrap.lua")()
end

require("lazy.minit").setup({
	spec = {
		{
			"echasnovski/mini.test",
			opts = function(_, opts)
				local test = require("mini.test")
				local filter = vim.env.TEST_FILTER
				opts.collect.filter_cases = function(case)
					return not filter or table.concat(case.desc, " | "):find(filter, 1, true) ~= nil
				end
				local reporter = test.gen_reporter.stdout({ group_depth = 3 })
				local start = reporter.start
				reporter.start = function(cases)
					if #cases == 0 then
						io.stderr:write("No test cases matched; check the file paths and TEST_FILTER.\n")
						vim.cmd("cquit 1")
					end
					start(cases)
				end
				opts.execute = { reporter = reporter }
			end,
		},
		{
			dir = vim.fn.getcwd(),
			opts = {},
		},
	},
})

vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
