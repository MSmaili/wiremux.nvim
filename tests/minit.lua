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
		"echasnovski/mini.test",
		{
			dir = vim.fn.getcwd(),
			opts = {},
		},
	},
})

vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
