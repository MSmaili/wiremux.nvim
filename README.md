# wiremux.nvim

wiremux is a small Neovim plugin that sends text to tmux panes/windows.

I built it for an AI workflow: I keep `opencode` / `claudecode` running in a dedicated tmux pane/window, then I send it context (selection, diagnostics, git diff, quickfix) with a keymap. No copy/paste and no context switching.

The original inspiration was [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim). wiremux aims to stay simpler and more tmux-first, while still being flexible enough to drive anything (AI, test runners, dev servers, REPLs).

**Key features:**

- **Persistent targets:** Your AI assistant survives Neovim restarts (state stored in tmux, not Neovim)
- **Context placeholders:** Send `{file}`, `{position}`, `{selection}`, `{diagnostics}`, `{changes}`, etc.
- **Flexible filtering:** Control which targets are visible (by origin, by directory, or global)
- **Zero startup cost:** Lazy-loaded, nothing runs until you use it
- **Prompt library:** Send pre-defined prompts with context injection

## Requirements

- Neovim 0.10+
- tmux 3.0+ recommended
- Neovim must run inside tmux

## Installation

### lazy.nvim

```lua
{
  "MSmaili/wiremux.nvim",
  dependencies = {
    -- Optional: nicer picker UI
    "ibhagwan/fzf-lua",
  },
  opts = {
    -- see Setup
  },
}
```

### packer.nvim

```lua
use {
  "MSmaili/wiremux.nvim",
  requires = { "ibhagwan/fzf-lua" }, -- optional
  config = function()
    require("wiremux").setup()
  end,
}
```

## Setup

Targets are named tmux panes/windows wiremux can create, focus, close, and send text to.

```lua
require("wiremux").setup({
  targets = {
    definitions = {
      opencode = {
        cmd = "opencode",
        kind = "pane",     -- "pane" | "window" (default: pane)
        split = "vertical", -- for panes: "horizontal" | "vertical"
      },
      claudecode = {
        cmd = "claudecode",
        kind = "pane",
        split = "horizontal",
      },
      -- Run directly (no shell wrapper). When the program exits, tmux closes the pane.
      ai_direct = {
        cmd = "opencode",
        kind = "pane",
        shell = false,
      },
    },
  },
})
```

Notes:

- You can create multiple panes/windows and then pick when sending to the target. You have behaviour option which you decide what to hapen
- `shell = true` (default) means: create a pane and then type `cmd` into it.
- `shell = false` means: pass `cmd` directly to tmux when creating the pane/window.
  This is useful for "run the tool directly and let tmux close the pane when it exits".

## How I Use It (Real-world config)

I run multiple instances(panes/windows) one for example an AI (opencode, claude, kiro) and anther instance running tests or some dev scripts and switch between them.
Here is my actual lazy.nvim configuration:

<details>
<summary>Click to expand full configuration</summary>

```lua
{
  "MSmaili/wiremux.nvim",
  opts = {
    picker = "fzf-lua",
    targets = {
      definitions = {
        -- AI assistants (shell=false: pane closes when AI exits)
        opencode = { cmd = "opencode", kind = "pane", shell = false, split = "horizontal" },
        claude = { cmd = "claude", kind = "pane", shell = false, split = "horizontal" },
        kiro = { cmd = "kiro-cli", kind = "pane", shell = false, split = "horizontal" },
        -- Interactive shells
        shell = { kind = "window", shell = true, split = "horizontal" },
        shell_pane = { kind = "pane", shell = true, split = "horizontal" },
      },
    },
  },
  keys = {
    -- Toggle visibility of last used target
    { "<leader>aa", function() require("wiremux").toggle() end, desc = "Toggle target" },
    -- Create new target from definitions
    { "<leader>ac", function() require("wiremux").create() end, desc = "Create target" },
    -- Send file path
    { "<leader>af", function() require("wiremux").send("{file}", { focus = true }) end, desc = "Send file" },
    -- Send "this" (position + selection in visual mode)
    { "<leader>at", function() require("wiremux").send("{this}", { focus = true }) end, mode = { "x", "n" }, desc = "Send this" },
    -- Send visual selection
    { "<leader>av", function() require("wiremux").send("{selection}", { focus = true }) end, mode = { "x" }, desc = "Send selection" },
    -- Send diagnostics
    { "<leader>ad", function() require("wiremux").send("{diagnostics}", { focus = true }) end, desc = "Send line diagnostics" },
    { "<leader>aD", function() require("wiremux").send("{diagnostics_all}", { focus = true }) end, desc = "Send all diagnostics" },
    -- Send via motion (operator)
    { "ga", function() return require("wiremux").send_motion() end, mode = { "x", "n" }, expr = true, desc = "Send motion" },
    -- Prompt library
    {
      "<leader>ap",
      function()
        require("wiremux").send({
          { name = "Review changes", text = "Can you review my changes?\n{changes}" },
          { name = "Fix diagnostics (file)", text = "Can you help me fix the diagnostics in {file}?\n{diagnostics_all}" },
          { name = "Fix diagnostics (line)", text = "Can you help me fix this diagnostic?\n{diagnostics}" },
          { name = "Add docs", text = "Add documentation to {this}" },
          { name = "Explain", text = "Explain {this}" },
          { name = "Fix", text = "Can you fix {this}?" },
          { name = "Optimize", text = "How can {this} be optimized?" },
          { name = "Review file", text = "Can you review {file} for any issues?" },
          { name = "Write tests", text = "Can you write tests for {this}?" },
          { name = "Fix quickfix", text = "Can you help me fix these issues?\n{quickfix}" },
        })
      end,
      mode = { "n", "x" },
      desc = "Select prompt",
    },
  },
}
```

</details>

**Key patterns:**

- **`{this}`** — My most used placeholder. In normal mode it sends position. In visual mode it sends position + selection.
- **`shell = false`** — When the AI exits, tmux closes the pane. No zombie shells.
- **`ga` operator** — `gaiw` sends inner word, `gaap` sends paragraph, visual + `ga` sends selection.

## Placeholders (context)

wiremux expands `{placeholders}` before sending.

Built-in placeholders are implemented in `lua/wiremux/context/builtins.lua`:

| Placeholder         | What it expands to                             |
| ------------------- | ---------------------------------------------- |
| `{file}`            | current buffer path                            |
| `{filename}`        | basename of `{file}`                           |
| `{position}`        | `file:line:col` (1-based line/col)             |
| `{line}`            | current line text                              |
| `{selection}`       | visual selection (empty if not in visual mode) |
| `{this}`            | `{position}` plus `{selection}` when available |
| `{diagnostics}`     | diagnostics on current line                    |
| `{diagnostics_all}` | all diagnostics in current buffer              |
| `{quickfix}`        | formatted quickfix list                        |
| `{buffers}`         | list of listed, loaded buffers                 |
| `{changes}`         | `git diff HEAD -- {file}` (or "No changes")    |

You can also add your own:

```lua
require("wiremux").setup({
  context = {
    resolvers = {
      git_branch = function()
        local result = vim.system({ "git", "branch", "--show-current" }, { text = true }):wait()
        return result.code == 0 and vim.trim(result.stdout) or nil
      end,
    },
  },
})
```

## Commands

```vim
:Wiremux send <text>
:Wiremux send-motion
:Wiremux focus
:Wiremux create
:Wiremux close
:Wiremux toggle
```

## Help

- `:h wiremux`
- `:h :Wiremux`

## Behaviors

Most actions can run in one of these modes:

- `pick`: show a picker when more than one instance avaiable
- `last`: reuse the last used target
- `all`: apply to all matching targets

In other words this means, when you press the action based on the behaviour we show a picker or the last one.

## Troubleshooting

- Run :checkhealth wiremux`.
- Make sure Neovim is running inside tmux (`$TMUX` is set).

## Persistence

wiremux stores target metadata in tmux pane variables (not in Neovim). This means:

- Your AI assistant survives Neovim restarts and crashes
- Multiple Neovim instances can share the same targets
- No state files or complex persistence logic needed

When you restart Neovim, wiremux will still see your previously created targets and can continue sending to them.

## Filters

Filters control which targets appear in pickers. This matters when you have multiple Neovim instances or want to share AI assistants (instances) across projects.

**Default (by origin):** Only show targets created from your current Neovim pane. Keeps your instances private to your current editor instance.

**By working directory:** Show all targets created from the same directory. Useful for sharing one instances per project across multiple Neovim instances.

**No filter:** Show all targets globally. One instance for everything.

```lua
-- Share targets within the same project directory
require("wiremux").setup({
  filter = {
    instances = function(inst, state)
      return inst.origin_cwd == vim.fn.getcwd()
    end,
  },
})
```

See `:h wiremux-filters` for all options and per-action filters.

## Performance

wiremux is designed to have minimal impact on your editor:

- **Lazy loaded:** Nothing is loaded until you actually use a feature
- **Zero startup cost:** The plugin adds no overhead to Neovim startup
- **State in tmux:** No background processes or timers running in Neovim
- **On-demand resolution:** Targets are queried from tmux only when needed, and number of IPC calls is minimal

## Disclamer

AI assisted tools were used during development, but all generated code was reviewed, understood, and adjusted manually.
The design and implementation decisions are intentional, and the plugin is kept deliberately simple and minimal.

## Credits

- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) — Inspiration for the idea and reference for a few implementation patterns.
