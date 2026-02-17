# wiremux.nvim

wiremux is a small Neovim plugin that sends text to tmux panes/windows.

![demo](https://github.com/MSmaili/wiremux.nvim/releases/download/v2.0.0/demo.gif)

Think of it as a way to wire up your editor to anything running in tmux:

- AI assistants,
- test runners,
- dev servers.

You define targets, create instances of them, and send text with context placeholders like `{file}`, `{selection}` etc.

**Key features:**

- **Persistent targets** -> state lives in tmux, so your targets survives Neovim restarts
- **Context placeholders** -> `{file}`, `{selection}`, `{diagnostics}`, `{changes}`, etc.
- **Command picker** -> pass a list of prompts/commands to `send()` and pick from them
- **Flexible filtering** -> control which targets show up per-action or globally
- **Zero startup cost** -> lazy-loaded, nothing runs until you use it

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
    -- see Quick Start
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

## Quick Start

A **target** is a named definition for a tmux pane or window that wiremux can create, send text to, and manage.

```lua
require("wiremux").setup({
  picker = { adapter = "fzf-lua" },
  targets = {
    definitions = {
      opencode = { cmd = "opencode", kind = "pane", split = "horizontal", shell = false },
      claude   = { cmd = "claude",   kind = "pane", split = "horizontal", shell = false },
      shell    = { kind = "pane",    split = "horizontal" },
    },
  },
})
```

### Target Definition Fields

| Field   | Type                            | Default        | Description                                                    |
| ------- | ------------------------------- | -------------- | -------------------------------------------------------------- |
| `cmd`   | `string?`                       | —              | Command to run when creating the pane/window                   |
| `kind`  | `"pane"` \| `"window"` \| table | `"pane"`       | Target kind. Table like `{"pane","window"}` prompts at runtime |
| `split` | `"horizontal"` \| `"vertical"`  | `"horizontal"` | Split direction (only for panes)                               |
| `shell` | `boolean`                       | `true`         | `true`: types `cmd` into a shell. `false`: runs `cmd` directly |
| `label` | `string` \| `function?`         | target name    | Display name in picker. Function: `fn(inst, index) -> string`  |
| `title` | `string?`                       | label or name  | Tmux window name (only used when `kind = "window"`)            |

<details>
<summary><strong>Default Options</strong></summary>

These are the full defaults from `config.lua`. You only need to override what you want to change.

```lua
{
  log_level = "warn",

  targets = {
    definitions = {},  -- your target definitions go here
  },

  actions = {
    close  = { behavior = "pick" },
    create = { behavior = "pick",  focus = true },
    send   = { behavior = "pick",  focus = true },
    focus  = { behavior = "last",  focus = true },
    toggle = { behavior = "last",  focus = false },
  },

  context = {
    resolvers = {},  -- custom placeholder resolvers
  },

  picker = {
    adapter = nil,  -- "fzf-lua" | "vim.ui.select" | custom function
    instances = {
      filter = function(inst, state)        -- default: filter by origin pane
        return inst.origin == state.origin_pane_id
      end,
      sort = function(a, b)                 -- default: most recently used first
        return (a.last_used_at or 0) > (b.last_used_at or 0)
      end,
    },
    targets = {
      filter = nil,
      sort = nil,
    },
  },
}
```

</details>

<details>
<summary><strong>Full Setup Example</strong></summary>

My actual lazy.nvim config — multiple AI assistants, project-aware commands, and a quick shell target:

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
        quick = { kind = { "pane", "window" }, shell = false, split = "horizontal" },
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
          { label = "npm test", value = "npm test; exec $SHELL", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },
          { label = "npm run build", value = "npm run build", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },
          { label = "npm run start", value = "npm run start", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },
          { label = "go build", value = "go build", submit = true, visible = function() return vim.bo.filetype == "go" end },
          { label = "go test (all)", value = "go test ./...", submit = true, visible = function() return vim.bo.filetype == "go" end },
          { label = "go test (selection)", value = "go test -run '{selection}'", submit = true, visible = function() return vim.bo.filetype == "go" and require("wiremux.context").is_available("selection") end },
        },
        {
            mode = "definitions", -- this makes possible to show only the target definitions
            filter = {
                definitions = function(name) return name == "quick" end,
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

## Sending Text

The `send()` function is the main way to interact with targets. You can send a string directly, or pass a table of items to create a picker.

**String mode** — sends text directly:

```lua
require("wiremux").send("{file}", { focus = true })
require("wiremux").send("{selection}")
```

**Picker mode** — pass a table of items and wiremux shows a picker to choose from:

```lua
require("wiremux").send({
  { label = "Explain",      value = "Explain {this}" },
  { label = "Review",       value = "Can you review my changes?\n{changes}" },
  { label = "Write tests",  value = "Can you write tests for {this}?" },
  { label = "Run tests",    value = "npm test; exec $SHELL", submit = true }, -- the exec $SHELL is useful if running on a non-shel env, and you want to keep open on failure
})
```

### SendItem Fields

| Field     | Type                   | Description                                  |
| --------- | ---------------------- | -------------------------------------------- |
| `value`   | `string`               | **(Required)** The text or command to send   |
| `label`   | `string?`              | Display name in picker (defaults to `value`) |
| `title`   | `string?`              | Custom tmux window name (optional)           |
| `submit`  | `boolean?`             | Auto-submit after sending (default: `false`) |
| `visible` | `boolean \| function?` | Show/hide item (default: `true`)             |

### Filtering Targets Per-Action

You can override which targets and instances show up for a specific `send()` call:

```lua
-- Only show "quick" definitions, skip existing instances
require("wiremux").send({ ... }, {
  mode = "definitions",
  filter = {
    definitions = function(name) return name == "quick" end,
  },
})
```

## Placeholders

wiremux expands `{placeholders}` before sending.

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

You can add custom placeholders:

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

Display the number of active wiremux targets in your statusline.

```lua
-- lualine
{
  require("wiremux").statusline.component(),
  padding = { left = 1, right = 1 },
}

-- heirline / feline
{ provider = require("wiremux").statusline.component() }
```

<img width="221" height="55" alt="image" src="https://github.com/user-attachments/assets/c95f24b8-a121-4b75-a83c-07b1639cb75f" />

For full control, use `get_info()`:

```lua
function()
  local info = require("wiremux").statusline.get_info()
  if info.count == 0 then return "" end
  local icon = info.last_used.kind == "window" and "󰖯" or "󰆍"
  return string.format("%s %d", icon, info.count)
end
```

**API:** `statusline.get_info()` returns `{ loading, count, last_used }` — `statusline.component()` returns a lualine-compatible function — `statusline.refresh()` forces an immediate refresh.

## Commands

```vim
:Wiremux send <text>
:Wiremux send-motion
:Wiremux focus
:Wiremux create
:Wiremux close
:Wiremux toggle
```

## Behaviors

Actions run in one of three behaviors:

- **`pick`** — show a picker when multiple instances are available
- **`last`** — reuse the most recently used target
- **`all`** — show all targets

Set globally in `actions` config or override per-call via opts.

### Mode

`send()` and `toggle()` default to `mode = "auto"` — they try existing instances first, and fall back to creating from definitions if none exist. You can override this:

- **`auto`** — instances first, fall back to definitions (default for send/toggle)
- **`instances`** — only show existing instances
- **`definitions`** — only show target definitions (useful for "run command" flows)
- **`all`** — show instances and definitions

```lua
-- Only offer to create new targets, skip existing instances
require("wiremux").send({ ... }, { mode = "definitions" })
```

## Filters

Filters control which targets appear in pickers.

**Global filters** — set in `picker.instances.filter` and `picker.targets.filter`:

```lua
picker = {
  instances = {
    -- Default: only show instances from current Neovim pane
    filter = function(inst, state) return inst.origin == state.origin_pane_id end,
    -- By working directory instead:
    filter = function(inst, state) return inst.origin_cwd == vim.fn.getcwd() end,
    -- Show everything:
    filter = nil,
  },
}
```

**Per-action filters** — override for a specific call:

```lua
require("wiremux").send("{file}", {
  filter = { instances = function(inst, state) return inst.origin_cwd == vim.fn.getcwd() end },
})
```

## Persistence

wiremux stores state in tmux pane variables — not in Neovim. Your targets survive editor restarts, and multiple Neovim instances can share them.

## Troubleshooting

- Run `:checkhealth wiremux`
- Make sure Neovim is running inside tmux (`$TMUX` is set)

## Help

- `:h wiremux`

## Credits

- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) — inspiration for the idea and reference for a few implementation patterns

AI-assisted tools were used during development. All generated code was reviewed and adjusted manually.
