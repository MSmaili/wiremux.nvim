# wiremux.nvim

wiremux is a small Neovim plugin that sends text to tmux panes/windows.

The original inspiration was [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim). wiremux aims to stay simpler and more tmux-first, while still being flexible enough to drive anything (AI, test runners, dev servers, REPLs).

Initially I built just as a small replacment of sidekick (wanted to be only with multiplexer mode and to have more control), but then the desire to add things grove and now I use it also for running different commands, and have a flexibile filter/sorts for showing things

**Key features:**

- **Persistent targets:** Your AI assistant survives Neovim restarts (state stored in tmux, not Neovim)
- **Context placeholders:** Send `{file}`, `{position}`, `{selection}`, `{diagnostics}`, `{changes}`, etc.
- **Flexible filtering:** Control which targets are visible (by origin, by directory, or global)
- **Zero startup cost:** Lazy-loaded, nothing runs until you use it
- **Custom list of commands:** Send pre-defined prompts/commands with context injection

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
  picker = {
    adapter = "fzf-lua", -- "fzf-lua" | "vim.ui.select" | custom function
    instances = {
      filter = function(inst, state)  -- optional, default: filter by origin
        return inst.origin == state.origin_pane_id
      end,
      sort = function(a, b)  -- optional, default: sort by recency (most recent first)
        return (a.last_used_at or 0) > (b.last_used_at or 0)
      end,
    },
    targets = {
      filter = nil,  -- optional, no default filter
      sort = nil,    -- optional, no default sort
    },
  },
  targets = {
    definitions = {
      opencode = {
        cmd = "opencode",
        kind = "pane",     -- "pane" | "window" | {"pane", "window"} (default: pane)
                           -- table = prompt to choose at runtime
        split = "vertical", -- for panes: "horizontal" | "vertical"
        label = "OpenAI",  -- custom display name (optional, string or function)
        title = "AI-Chat", -- custom tmux window name (optional, defaults to label or target)
      },
      claudecode = {
        cmd = "claudecode",
        kind = "pane",
        split = "horizontal",
        label = "Claude", -- can also be a function, see examples below
        title = "Claude-Chat",
      },
      -- Run directly (no shell wrapper). When the program exits, tmux closes the pane.
      ai_direct = {
        cmd = "opencode",
        kind = "pane",
        shell = false,
      },
      -- Runtime choice: prompts to select pane or window each time we create
      flexible = {
        cmd = "htop",
        kind = { "pane", "window" },
        shell = false, -- closes when htop exits
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
- `label` can be a string or function: `fun(inst: wiremux.Instance, index: number): string` for dynamic picker display.
- `title` sets the tmux window name (only used when `kind = "window"`). Defaults to `label` (if string) or target name.

## How I Use It

I run multiple instances(panes/windows) one for example an AI (opencode, claude, kiro) and anther instance running tests or some dev scripts and switch between them.
Here is my actual lazy.nvim configuration:

<details>
<summary>Click to expand full configuration</summary>

```lua
{
  "MSmaili/wiremux.nvim",
  opts = {
    picker = { adapter = "fzf-lua" },
    targets = {
      definitions = {
        -- AI assistants (shell=false: pane closes when AI exits)
        opencode = { cmd = "opencode", kind = { "pane", "window" }, shell = false, split = "horizontal" },
        claude = { cmd = "claude", kind = { "pane", "window" }, shell = false, split = "horizontal" },
        kiro = { cmd = "kiro-cli", kind = { "pane", "window" }, shell = false, split = "horizontal" },
        -- Interactive shells
        shell = { kind = { "pane", "window" }, shell = true, split = "horizontal" },
        quick = { kind = { "pane", "window" }, shell = false, split = "horizontal" }, -- for running custom commands
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
    { "<leader>aD", function() require("wiremux").send("{diagnostics_all}", { focus = true }) end, desc = "Send all diagnostics on current buffer" },
    -- Send via motion (operator)
    { "ga", function() return require("wiremux").send_motion() end, mode = { "x", "n" }, expr = true, desc = "Send motion" },
    {
      "<leader>ap",
      function()
        require("wiremux").send({
          -- AI Prompts
          { label = "Review changes", value = "Can you review my changes?\n{changes}" },
          { label = "Fix diagnostics (file)", value = "Can you help me fix the diagnostics in {file}?\n{diagnostics_all}", visible = function() return require("wiremux.context").is_available("diagnostics_all") end },
          { label = "Fix diagnostics (line)", value = "Can you help me fix this diagnostic?\n{diagnostics}", visible = function() return require("wiremux.context").is_available("diagnostics") end },
          { label = "Add docs", value = "Add documentation to {this}" },
          { label = "Explain", value = "Explain {this}" },
          { label = "Fix", value = "Can you fix {this}?" },
          { label = "Optimize", value = "How can {this} be optimized?" },
          { label = "Review file", value = "Can you review {file} for any issues?" },
          { label = "Write tests", value = "Can you write tests for {this}?" },
          { label = "Fix quickfix", value = "Can you help me fix these issues?\n{quickfix}", visible = function() return require("wiremux.context").is_available("quickfix") end },
        })
      end,
      mode = { "n", "x" },
      desc = "AI prompts",
    },
    -- Run project commands (context-aware)
    {
      "<leader>ar",
      function()
        require("wiremux").send({
          -- Node.js commands
          { label = "npm test", value = "npm test; exec $SHELL", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },-- with execute shell is like saying shell = false, but only for this
          { label = "npm run build", value = "npm run build", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },
          { label = "npm run start", value = "npm run start", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },
          -- Go commands
          { label = "go build", value = "go build", submit = true, visible = function() return vim.bo.filetype == "go" end },
          { label = "go test (all)", value = "go test ./...", submit = true, visible = function() return vim.bo.filetype == "go" end },
          { label = "go test (selection)", value = "go test -run '{selection}'", submit = true, visible = function() return vim.bo.filetype == "go" and require("wiremux.context").is_available("selection") end },
        },
        {
            filter = {
                definitions = function(name, def) -- run commands on a new quick target
                    return name == "quick"
                end,
                instances = function() -- hide instances, i just want to run commands and create new instance
                    return false
                end,
            },
            behavior = "pick",
        })
      end,
      desc = "Run project command",
    },
  },
}
```

</details>

### SendItem (Prompt/Command) Fields

When using `send()` with an array of items, each item supports these fields:

| Field     | Type                   | Description                                     |
| --------- | ---------------------- | ----------------------------------------------- |
| `value`   | `string`               | **(Required)** The text or command to send      |
| `label`   | `string?`              | Display name in picker (defaults to `value`)    |
| `title`   | `string?`              | Custom tmux window / zellij tab name (optional) |
| `submit`  | `boolean?`             | Auto-submit after sending (default: `false`)    |
| `visible` | `boolean \| function?` | Show/hide item (default: `true`)                |

**Examples:**

```lua
-- Basic prompt (label optional)
{ value = "Explain {this}" }

-- Command with auto-submit
{ label = "Run tests", value = "npm test", submit = true }

-- Conditional visibility (only show when selection available)
{
  label = "Test selection",
  value = "jest -t '{selection}'",
  visible = function()
    return require("wiremux.context").is_available("selection")
  end
}

-- Filetype-specific command
{
  label = "Cargo test",
  value = "cargo test",
  submit = true,
  visible = function() return vim.bo.filetype == "rust" end
}

-- Dynamic window title
{
  label = "Run server",
  value = "npm run dev",
  title = "Dev-Server",  -- tmux window will be named "Dev-Server"
  submit = true,
}
```

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

## Statusline

Display the number of active wiremux targets in your statusline. Updates instantly when targets are created, focused, or closed.

### Quick Start

Works with any statusline plugin. Add the component:

```lua
-- lualine
{
  require("wiremux").statusline.component(),
  padding = { left = 1, right = 1 },
}

-- heirline (provider function)
{ provider = require("wiremux").statusline.component() }

-- feline (component)
{ provider = require("wiremux").statusline.component() }
```

Shows `󰆍 3 [latest_target_name]` when targets exist, nothing when empty. Automatically hidden outside tmux.

### Custom Statusline

Use `get_info()` for full control:

```lua
local info = require("wiremux").statusline.get_info()
-- info.loading  → true during initial fetch
-- info.count    → number of targets (0, 1, 2...)
-- info.last_used → { id, target, kind, name }

-- Example: custom format with different icons for pane vs window
function()
  local info = require("wiremux").statusline.get_info()
  if info.count == 0 then return "" end

  local icon = info.last_used.kind == "window" and "󰖯" or "󰆍"
  return string.format("%s %d", icon, info.count)
end

-- Example: show target name only (no count)
function()
  local info = require("wiremux").statusline.get_info()
  if info.last_used then
    return "[" .. info.last_used.name .. "]"
  end
  return ""
end
```

### API Reference

- `statusline.get_info()` — Returns `{ loading, count, last_used }`
- `statusline.component()` — Returns lualine component function
- `statusline.refresh()` — Force immediate refresh (blocking)

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

## Behaviors

Most actions can run in one of these modes:

- `pick`: show a picker when more than one instance avaiable
- `last`: reuse the last used target
- `all`: apply to all matching targets

In other words this means, when you press the action based on the behaviour we show a picker or we send to the last used instance.
Behaviour can be changed globaly or per action

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

**Default (by origin):** Only show instances created from your current Neovim pane. Keeps your instances private to your current editor instance.

**By working directory:** Show all instances created from the same directory. Useful for sharing instances per project across multiple Neovim instances.

**No filter:** Show all instances globally. One instance for everything.

### Global Filters

Set default filters in `picker.instances.filter` and `picker.targets.filter`:

```lua
require("wiremux").setup({
  picker = {
    instances = {
      -- Default: filter by origin (current Neovim pane)
      filter = function(inst, state)
        return inst.origin == state.origin
      end,
    },
    targets = {
      -- No default filter for target definitions
      filter = nil,
    },
  },
})
```

### Common Filter Examples

```lua
require("wiremux").setup({
  picker = {
    instances = {
      -- Show all instances globally (no filtering)
      filter = nil,

      -- OR: Filter by working directory
      filter = function(inst, state)
        return inst.origin_cwd == vim.fn.getcwd()
      end,
    },
  },
})
```

### Per-Action Filters

Override global filters for specific actions using `opts.filter`:

```lua
-- Use global filter for most actions, but show all instances for this one
require("wiremux").send("{file}", {
  focus = true,
  filter = nil  -- Override global filter to show all instances
})

-- Filter by directory for this specific action
require("wiremux").focus({
  filter = function(inst, state)
    return inst.origin_cwd == vim.fn.getcwd()
  end
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
A bigger usage of AI was writing tests and docs.

## Credits

- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) — Inspiration for the idea and reference for a few implementation patterns.
