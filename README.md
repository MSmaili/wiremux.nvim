# wiremux.nvim

Send text from Neovim to tmux panes and windows - perfect for AI assistants, terminals, and dev tools.

https://github.com/user-attachments/assets/77d5735d-515b-467e-87c5-417189a6359e

## What is wiremux?

Wiremux connects your editor to anything running in tmux. Common uses:

- **Chat with AI assistants** (Claude, OpenCode, etc.) about your code
- **Run tests or build commands** without leaving your editor
- **Quick terminal access** for any shell commands

It works by creating "targets" (tmux panes/windows) and sending them text with smart placeholders like `{file}`, `{selection}`, or `{this}`.

### Why wiremux?

- **Persistent** - Your targets survive Neovim restarts (stored in tmux)
- **Smart text** - Send context-aware snippets with placeholders
- **Zero startup cost** - Lazy-loaded, nothing runs until you use it

## Requirements

- Neovim 0.10+
- tmux 3.0+ recommended
- Neovim must run inside tmux

## Installation

Add wiremux to your plugin manager. Optional picker dependencies like `fzf-lua` or `snacks.nvim` give you a nicer picker interface.

### lazy.nvim (recommended)

```lua
{
  "MSmaili/wiremux.nvim",
  dependencies = {
    "ibhagwan/fzf-lua", -- optional
    "folke/snacks.nvim", -- optional
  },
  opts = {},
}
```

### Other Managers

```lua
-- packer.nvim
use {
  "MSmaili/wiremux.nvim",
  requires = { "ibhagwan/fzf-lua" }, -- optional
  config = function()
    require("wiremux").setup()
  end,
}

-- vim-plug
Plug 'MSmaili/wiremux.nvim'
```

<details>
<summary><strong>Default Configuration</strong></summary>

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
    send   = { behavior = "pick",  focus = true, compose = false },
    focus  = { behavior = "last",  focus = true },
    toggle = { behavior = "last",  focus = false },
  },

  context = {
    resolvers = {},  -- custom placeholder resolvers
  },

  picker = {
    adapter = nil,  -- "fzf-lua" | "snacks" | custom function
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

  ui = {
    compose = {
      width = 0.6,
      height = 0.4,
      title = " Compose Message ",
      border = "rounded",
      style = "minimal",
      close_behavior = "ask",  -- "ask" | "hide" | "discard"
      on_new_payload = "ask",  -- "ask" | "keep" | "replace" | "append"
      wo = { wrap = true, number = false, relativenumber = false },
      capture_placeholders = {
        "file", "filename", "position", "line", "selection", "this",
      },
      keymaps = {
        send = {
          { "<C-s>", mode = "i", desc = "Send to target" },
          { "<CR>", mode = "n", desc = "Send to target" },
        },
        close = {
          { "q", mode = "n", desc = "Close draft" },
          { "<Esc>", mode = "n", desc = "Close draft" },
        },
        files = {
          { "<C-f>", mode = { "n", "i" }, desc = "Insert file" },
        },
        previous = { "<C-p>", mode = "n", desc = "Previous compose page" },
        next = { "<C-n>", mode = "n", desc = "Next compose page" },
      },
    },
  },
}
```

`picker.adapter` accepts either a named adapter like `"fzf-lua"` or `"snacks"`, or a custom
function for item selection. Compose file insertion uses the adapter's
`files()` picker when available, otherwise wiremux falls back to its built-in
file list picker using the active selection picker.

</details>

## Quick Start

### Step 1: Define Your First Target

A **target** is a tmux pane or window that wiremux manages. Add this minimal setup:

```lua
require("wiremux").setup({
  targets = {
    definitions = {
      -- A simple terminal
      terminal = { kind = "pane", split = "horizontal" },
    },
  },
})
```

<details>
<summary><strong>Target Definition Fields Reference</strong></summary>

| Field        | Type                            | Default        | Description                                                          |
| ------------ | ------------------------------- | -------------- | -------------------------------------------------------------------- |
| `cmd`        | `string?`                       | -              | Command to run when creating the pane/window                         |
| `kind`       | `"pane"` \| `"window"` \| table | `"pane"`       | Target type. Use table like `{"pane","window"}` to prompt at runtime |
| `split`      | `"horizontal"` \| `"vertical"`  | `"horizontal"` | Split direction (panes only)                                         |
| `split_mode` | `"before"` \| `"after"`         | `"after"`      | Split placement relative to source pane (panes only)                 |
| `shell`      | `boolean`                       | `true`         | `true`: types `cmd` into a shell. `false`: runs `cmd` directly       |
| `label`      | `string` \| `function?`         | target name    | Display name in picker                                               |
| `title`      | `string?`                       | label or name  | Tmux window name (windows only)                                      |

</details>

### Step 2: Create and Use It

Run `:Wiremux create` — a picker appears listing your defined targets. Select "terminal" and wiremux opens a tmux pane. Or use Lua:

```lua
-- Create the target (opens a tmux pane)
require("wiremux").create()

-- Send text to it
require("wiremux").send("ls -la")
```

### Step 3: Add Keyboard Shortcuts

```lua
-- Using lazy.nvim keys:
keys = {
  -- Toggle terminal visibility
  { "<leader>tt", function() require("wiremux").toggle() end, desc = "Toggle terminal" },
  -- Send current file path
  { "<leader>tf", function() require("wiremux").send("{file}") end, desc = "Send file path" },
  -- Send visual selection
  { "<leader>tv", function() require("wiremux").send("{selection}") end, mode = "x", desc = "Send selection" },
}
```

### Understanding the Basics

Two key concepts to remember:

| Concept        | What it is                                           | Example                             |
| -------------- | ---------------------------------------------------- | ----------------------------------- |
| **Definition** | A template describing how to create a target         | `{ cmd = "claude", kind = "pane" }` |
| **Instance**   | A running tmux pane/window created from a definition | The actual claude pane open in tmux |

Definitions live in your config. Instances are created on-demand and persist in tmux.

## Sending Text

The `send()` function is your main tool. You can send simple strings or create a picker menu.

### Basic Sending

Send text directly to your target:

```lua
-- Send the current file path
require("wiremux").send("{file}")

-- Send with focus (jumps to the target pane)
require("wiremux").send("{selection}", { focus = true })

-- Send a custom message
require("wiremux").send("Hello from Neovim!")
```

### Using the Picker

Pass a list of items to get a menu:

```lua
require("wiremux").send({
  { label = "Explain this", value = "Explain {this}" },
  { label = "Review changes", value = "Review my changes:\n{changes}" },
  { label = "Run tests", value = "npm test", submit = true },
})
```

Each item in the picker can have:

| Field       | What it does                          | Example                                          |
| ----------- | ------------------------------------- | ------------------------------------------------ |
| `value`     | **(Required)** The text to send       | `"Explain {file}"`                               |
| `label`     | Display name in the picker            | `"Explain file"`                                 |
| `submit`    | Auto-press Enter after sending        | `true` (useful for commands)                     |
| `visible`   | Show/hide this item dynamically       | `function() return vim.bo.filetype == "lua" end` |
| `compose`   | Review before sending (`true` or `ui.compose` overrides) | `{ on_new_payload = "append" }` |
| `placeholders` | Expand placeholders; set `false` for literal source text | `false` |
| `pre_keys`  | Keystrokes to send before pasting     | `"C-c"`, `{"C-c", "i"}`                         |
| `post_keys` | Keystrokes to send after pasting      | `"Escape"`, `{"Escape", "Enter"}`                |

### Compose Drafts

Use compose mode to edit unresolved text before choosing a target:

```lua
require("wiremux").send("Review {this}", { compose = true })

require("wiremux").send("Review {selection}", {
  compose = {
    title = " Review Selection ",
    close_behavior = "hide",
    on_new_payload = "append",
  },
})
```

Set `on_new_payload = "append"` for one compose configuration to collect multiple editor locations into one paged draft. Each invocation becomes a page, normal-mode `<C-p>` and `<C-n>` navigate pages, and confirmation sends all pages once with a blank line between them:

```lua
-- Map this in normal or visual mode, then invoke it from each location.
vim.keymap.set({ "n", "x" }, "<leader>ar", function()
  require("wiremux").send("Review this context:\n{this}", {
    compose = {
      title = " Review Context ",
      close_behavior = "hide",
      on_new_payload = "append",
    },
    target = "claude",
  })
end)
```

Compose keeps placeholders raw while editing. Every page captures names already present plus the global `ui.compose.capture_placeholders` policy when it is added, so `{this}` from different files or selections uses the correct original location at confirmation time. The lightweight default policy contains `file`, `filename`, `position`, `line`, `selection`, and `this`. More expensive or potentially large placeholders such as `{changes}`, `{diagnostics}`, and `{diagnostics_all}` are captured only when present initially or explicitly added to the policy. Other placeholders typed later resolve at confirmation, while failed eager captures remain literal. A configured list replaces the default policy; set it to `{}` to disable extra pre-capture. Capture policy is not accepted in action, call-level, or item-level compose tables.

When a draft already exists, `on_new_payload` supports `"ask"`, `"keep"`, `"replace"`, and `"append"`. The ask dialog defaults to **Keep Draft**. Calling `send()` without text reopens an existing hidden draft without adding a page or changing its delivery options.

Compose option precedence is whole-value precedence: item-level `compose`, then call-level `opts.compose`, then `actions.send.compose`. Tables imply compose is enabled and are not merged across those levels. The selected table uses the same fields as `ui.compose` and is deep-merged over those global defaults for the compose session.

#### Customize Compose On Open

Wiremux emits the `User` event `WiremuxComposeOpen` after a compose window is fully configured and focused. Use it for editor preferences such as starting insert mode, enabling spell checking, or adding buffer-local mappings:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "WiremuxComposeOpen",
  callback = function(event)
    local buf = event.data.buf
    local win = event.data.win

    vim.wo[win].spell = true
    vim.keymap.set("n", "<leader>cc", function()
      vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
        "Please review the following:",
        "",
      })
    end, { buffer = buf, desc = "Insert review prompt" })

    vim.cmd("startinsert!")
  end,
})
```

The event data contains `buf`, `win`, and `reopened`. It fires on initial window creation with `reopened = false` and when a hidden draft window is recreated with `reopened = true`. It does not fire again when an already-visible compose window is merely focused. Register the autocmd before opening compose.

### Sending Keystrokes Before/After

Some TUI apps need keystrokes sent before/after the pasted text — for example, `C-c` to cancel any in-progress input, or `Escape` to return to a neutral state after pasting:

```lua
-- Cancel current input before pasting, return to normal state after
require("wiremux").send({
  value = "my text",
  pre_keys = { "C-c" },
  post_keys = { "Escape" },
})

-- Vim-mode editors: enter insert mode before pasting, Escape after
require("wiremux").send({
  value = "my text",
  pre_keys = { "i" },
  post_keys = { "Escape" },
})

-- Per-call opts: all items in this keymap use the same keys
require("wiremux").send({
  { label = "Explain", value = "Explain {this}" },
  { label = "Review", value = "Review {changes}" },
}, { pre_keys = { "i" }, target = "claude" })
```

Item-level `pre_keys`/`post_keys` override opts-level when both are set.

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

You can add custom placeholders. Resolver names must begin with a letter or underscore and continue with letters, digits, or underscores:

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

Custom resolvers should be fast and side-effect-free. If a custom resolver depends on the current editor page and users may type it after opening compose, add its name to the global capture policy:

```lua
ui = {
  compose = {
    capture_placeholders = {
      "file", "filename", "position", "line", "selection", "this",
      "git_branch",
    },
  },
}
```

## Advanced Configuration

### Target Resolution Options

When you run an action, wiremux decides which targets to show. You can control this with four options:

**1. Specific Target** - Skip the picker and use a named target:

```lua
require("wiremux").send("{this}", { target = "claude" })
require("wiremux").focus({ target = "claude" })
```

If matching instances exist, they're used. Otherwise wiremux falls back to creating from the definition. Filters still apply; if a filter excludes the target, it won't be found.

**2. Behavior** - How to handle multiple targets:

| Behavior | What happens           | Use when...                   |
| -------- | ---------------------- | ----------------------------- |
| `pick`   | Show picker to choose  | You want to select each time  |
| `last`   | Use most recent target | You want quick repeat actions |
| `all`    | Send to every target   | Broadcasting to multiple AIs  |

**3. Mode** - Where to look for targets (only for `send()` and `toggle()`):

| Mode          | What it shows                     | Use when...              |
| ------------- | --------------------------------- | ------------------------ |
| `auto`        | Instances first, then definitions | Default - smart fallback |
| `instances`   | Only existing panes/windows       | Managing current targets |
| `definitions` | Only templates to create new      | Starting fresh sessions  |
| `all`         | Everything                        | Full overview            |

**4. Filters** - Fine-grained control:

By default, only targets created from your current tmux pane are shown. You can override this:

```lua
-- Show all targets regardless of which pane created them
picker = {
  instances = {
    filter = nil,
  },
}

-- Only show targets from current directory
picker = {
  instances = {
    filter = function(inst, state)
      return inst.origin_cwd == vim.fn.getcwd()
    end,
  },
}
```

### Complete Real-World Setup

Here's a comprehensive example with multiple AIs, project commands, and smart filtering:

```lua
{
  "MSmaili/wiremux.nvim",
  opts = {
    picker = { adapter = "fzf-lua" },
    targets = {
      definitions = {
        -- AI assistants
        claude = { cmd = "claude", kind = { "pane", "window" }, shell = false },
        opencode = { cmd = "opencode", kind = { "pane", "window" }, shell = false },
        -- Interactive shell
        shell = { kind = { "pane", "window" }, shell = true },
        -- Quick command runner
        quick = { kind = { "pane", "window" }, shell = false },
      },
    },
  },
  keys = {
    { "<leader>aa", function() require("wiremux").toggle() end, desc = "Toggle target" },
    { "<leader>ac", function() require("wiremux").create() end, desc = "Create target" },
    -- Send context
    { "<leader>af", function() require("wiremux").send("{file}") end, desc = "Send file" },
    { "<leader>at", function() require("wiremux").send("{this}") end, mode = { "x", "n" }, desc = "Send this" },
    { "<leader>av", function() require("wiremux").send("{selection}") end, mode = "x", desc = "Send selection" },
    { "<leader>ad", function() require("wiremux").send("{diagnostics}") end, desc = "Send diagnostics" },
    -- Send motion (works like an operator: ga + motion, e.g. gaip sends a paragraph)
    { "ga", function() require("wiremux").send_motion() end, desc = "Send motion to target" },
    -- AI prompts picker
    {
      "<leader>ap",
      function()
        require("wiremux").send({
          { label = "Review changes", value = "Can you review my changes?\n{changes}" },
          { label = "Fix diagnostics", value = "Can you help me fix this?\n{diagnostics}", visible = function() return require("wiremux.context").is_available("diagnostics") end },
          { label = "Explain", value = "Explain {this}" },
          { label = "Write tests", value = "Can you write tests for {this}?" },
        })
      end,
      mode = { "n", "x" },
      desc = "AI prompts",
    },
    -- Project commands (only show "quick" target)
    {
      "<leader>ar",
      function()
        require("wiremux").send({
          { label = "npm test", value = "npm test; exec $SHELL", submit = true, visible = function() return vim.fn.filereadable("package.json") == 1 end },
          { label = "go test", value = "go test ./...", submit = true, visible = function() return vim.bo.filetype == "go" end },
        }, { mode = "definitions", filter = { definitions = function(name) return name == "quick" end } })
      end,
      desc = "Run command",
    },
  },
}
```

## Actions & Commands

These are the main ways to interact with wiremux targets. You can use them as **Lua functions** (for keybindings) or **Vim commands** (for command line):

| Lua Function    | Vim Command            | What it does                              | Common use case                                            |
| --------------- | ---------------------- | ----------------------------------------- | ---------------------------------------------------------- |
| `send()`        | `:Wiremux send <text>` | Sends text to a target                    | Send code, prompts, or commands to an AI or terminal       |
| `send_motion()` | `:Wiremux send-motion` | Sends text covered by a motion (operator) | Works like `y`: map to `ga`, then `gaip` sends a paragraph |
| `create()`      | `:Wiremux create`      | Creates a new target from a definition    | Start a new AI assistant or terminal pane                  |
| `toggle()`      | `:Wiremux toggle`      | Shows/hides the last used target          | Quick hide/show your AI or terminal                        |
| `focus()`       | `:Wiremux focus`       | Switches focus to a target                | Jump to your terminal or AI pane                           |
| `close()`       | `:Wiremux close`       | Closes a target                           | Shut down an AI or terminal you're done with               |
| `adopt()`       | `:Wiremux adopt`       | Re-owns an existing tmux pane             | Bring any existing pane under wiremux control              |

### Adopt Existing Panes

Use `:Wiremux adopt` or `require("wiremux").adopt()` to re-own an existing tmux pane from the current Neovim pane. By default, the picker shows all panes in the current tmux session, including unmanaged panes. The current pane is always excluded.

Unmanaged panes are assigned a generated target name like `pane-3`. Pass `target` when you want the adopted pane to use a specific wiremux target name:

```lua
require("wiremux").adopt({ target = "terminal" })
```

For Lua calls, `filter.instances` replaces the default adopt filter for that call. This lets you include cross-session panes from the queried tmux pane list:

```lua
require("wiremux").adopt({
  filter = {
    instances = function()
      return true -- all queried panes except the current pane
    end,
  },
})
```

You can combine `target` with a filter to adopt matching panes under a known target name:

```lua
require("wiremux").adopt({
  target = "terminal",
  filter = {
    instances = function(inst)
      return inst.running_command == "zsh"
    end,
  },
})
```

Use `format_item` to customize the adopt picker rows:

```lua
require("wiremux").adopt({
  format_item = function(pane)
    return string.format("%s %s %s", pane.target or "unmanaged", pane.id, pane.running_command or "")
  end,
})
```

**Tip:** Lua functions give you more power (placeholders, options, dynamic content), while commands are great for quick command-line use or when mapping from Vimscript.

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

**API:** `statusline.get_info()` returns `{ loading, count, last_used }` - `statusline.component()` returns a lualine-compatible function - `statusline.refresh()` forces an immediate refresh.

## Persistence

wiremux stores state in tmux pane variables, not in Neovim. Your targets survive editor restarts, and multiple Neovim instances can share them.

## Troubleshooting

- Run `:checkhealth wiremux`
- Make sure Neovim is running inside tmux (`$TMUX` is set)

## Help

- `:h wiremux`

## Credits

- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) - inspiration for the idea and reference for a few implementation patterns

AI-assisted tools were used during development. All generated code was reviewed and adjusted manually.
