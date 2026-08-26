# wiremux.nvim

Wiremux sends text from Neovim to tmux panes and windows. Use it to work with AI assistants, terminals, and development tools without leaving Neovim.

https://github.com/user-attachments/assets/77d5735d-515b-467e-87c5-417189a6359e

## What is Wiremux?

Wiremux connects Neovim to programs that run in tmux. You can use Wiremux to:

- Ask an AI assistant, such as Claude or OpenCode, about your code.
- Run tests and build commands.
- Send commands to a terminal.

Wiremux manages tmux panes and windows as **targets**. It sends text to these targets and can replace placeholders such as `{file}`, `{selection}`, and `{this}`.

### Why use Wiremux?

- **Persistent targets**: Targets remain available after you restart Neovim.
- **Context-aware text**: Placeholders add editor context to the text that you send.
- **No startup work**: Wiremux does not run until you use it.

## Requirements

- Neovim 0.11 or later
- tmux 3.0 or later (recommended)
- A Neovim session that runs inside tmux

## Installation

Add Wiremux to your plugin manager. You can also install `fzf-lua` or `snacks.nvim` for a different picker interface.

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

### Other plugin managers

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
<summary><strong>Default configuration</strong></summary>

The following example shows all default values from `config.lua`. Override only the values that you want to change.

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
      keymaps = {
        send = {
          { "<C-s>", mode = "i", desc = "Send to target" },
          { "<CR>", mode = "n", desc = "Send to target" },
        },
        close = {
          { "q", mode = "n", desc = "Close draft" },
          { "<Esc>", mode = "n", desc = "Close draft" },
        },
        -- discard has no default key. Set one to drop a draft without the
        -- close_behavior prompt, e.g.:
        -- discard = { "<C-d>", mode = "n", desc = "Discard draft" },
        files = {
          { "<C-f>", mode = { "n", "i" }, desc = "Insert file" },
        },
        delete_page = { "<C-x>", mode = "n", desc = "Delete compose page" },
        preview_placeholder = { "K", mode = "n", desc = "Preview placeholder" },
        previous = { "<C-p>", mode = "n", desc = "Previous compose page" },
        next = { "<C-n>", mode = "n", desc = "Next compose page" },
      },
    },
  },
}
```

Set `picker.adapter` to `"fzf-lua"`, `"snacks"`, or a custom selection function. When you insert a file, Wiremux first uses the adapter's `files()` picker. If that picker is not available, Wiremux shows its built-in file list with the active picker.

</details>

## Quick start

### Step 1: Define your first target

A **target** is a tmux pane or window that Wiremux manages. Add this minimal configuration:

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
<summary><strong>Target definition fields</strong></summary>

| Field        | Type                            | Default        | Description                                                         |
| ------------ | ------------------------------- | -------------- | ------------------------------------------------------------------- |
| `cmd`        | `string?`                       | -              | Command to run when Wiremux creates the pane or window              |
| `kind`       | `"pane"` \| `"window"` \| table | `"pane"`       | Target type. Use `{"pane","window"}` to select the type at run time |
| `split`      | `"horizontal"` \| `"vertical"`  | `"horizontal"` | Split direction (panes only)                                        |
| `split_mode` | `"before"` \| `"after"`         | `"after"`      | Split placement relative to source pane (panes only)                |
| `shell`      | `boolean`                       | `true`         | `true`: types `cmd` into a shell. `false`: runs `cmd` directly      |
| `label`      | `string` \| `function?`         | target name    | Display name in picker                                              |
| `title`      | `string?`                       | label or name  | Tmux window name (windows only)                                     |

</details>

### Step 2: Create and use the target

Run `:Wiremux create`. Wiremux shows a list of your target definitions. Select `terminal` to open its tmux pane. You can also use Lua:

```lua
-- Create the target (opens a tmux pane)
require("wiremux").create()

-- Send text to it
require("wiremux").send("ls -la")
```

### Step 3: Add keyboard shortcuts

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

### Understand the basic terms

Wiremux uses two main terms:

| Concept        | What it is                                              | Example                             |
| -------------- | ------------------------------------------------------- | ----------------------------------- |
| **Definition** | Configuration that tells Wiremux how to create a target | `{ cmd = "claude", kind = "pane" }` |
| **Instance**   | A running tmux pane or window created from a definition | A Claude pane that is open in tmux  |

Wiremux stores definitions in your configuration. It creates instances when necessary. Instances remain available in tmux.

## Sending text

Use `send()` to send text to a target or to show a selection menu.

### Send text directly

Send text directly to a target:

```lua
-- Send the current file path
require("wiremux").send("{file}")

-- Send with focus (jumps to the target pane)
require("wiremux").send("{selection}", { focus = true })

-- Send a custom message
require("wiremux").send("Hello from Neovim!")
```

### Select text from a menu

Pass a list of items to show a selection menu:

```lua
require("wiremux").send({
  { label = "Explain this", value = "Explain {this}" },
  { label = "Review changes", value = "Review my changes:\n{changes}" },
  { label = "Run tests", value = "npm test", submit = true },
})
```

Each item can contain these fields:

| Field          | Function                                                     | Example                                          |
| -------------- | ------------------------------------------------------------ | ------------------------------------------------ |
| `value`        | **Required.** Specifies the text to send                     | `"Explain {file}"`                               |
| `label`        | Specifies the item name in the picker                        | `"Explain file"`                                 |
| `submit`       | Presses Enter after Wiremux sends the text                   | `true` (useful for commands)                     |
| `visible`      | Controls whether Wiremux shows the item                      | `function() return vim.bo.filetype == "lua" end` |
| `compose`      | Opens a draft; accepts `true` or session options             | `{ on_new_payload = "append" }`                  |
| `placeholders` | Controls placeholder replacement; `false` sends literal text | `false`                                          |
| `pre_keys`     | Specifies keys to send before the text                       | `"C-c"`, `{"C-c", "i"}`                          |
| `post_keys`    | Specifies keys to send after the text                        | `"Escape"`, `{"Escape", "Enter"}`                |

### Compose drafts

Use compose mode to review and edit a placeholder template before you select a target:

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

Set `on_new_payload = "append"` to collect text from multiple editor locations. Each new input creates a page. Use `<C-p>` and `<C-n>` in normal mode to move between pages. Use `<C-x>` to delete the current page. Wiremux then selects the next page. If you delete the last page, Wiremux selects the first page. If the draft has one page, `<C-x>` clears its text. Wiremux sends the pages with a blank line between them:

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

Place the cursor on a placeholder and press `K` to preview its value. Press `K` again to focus the preview. Use `q` or `<Esc>` to close it. Wiremux shows `(empty)` for an empty value and a short message for an unavailable value. A `{changes}` preview uses diff syntax. The preview resolves the name once and does not change the page.

Wiremux keeps the placeholder template unchanged while you edit it. Each page stores the **origin** that it came from. One rule covers the whole model: **the origin holds frozen state, and everything else resolves when you send the draft.**

The origin holds the source path, row, column, visual selection, and the text of the source line. These values never change after Wiremux creates the page, so identical pages can produce different text from different editor locations. Every other value resolves at send time: buffer contents, diagnostics, Git output, `{buffers}`, and `{quickfix}`.

It does not matter when you type a placeholder. A name in the initial text and a name that you add later follow the same rule. If no value is available for a name, the placeholder remains literal, and Wiremux tries again the next time you send.

`{diagnostics}` and `{diagnostics_all}` need the source buffer. They remain literal if you delete that buffer, unless Wiremux finds a loaded buffer with the same path. Every other placeholder survives, because `{line}` and `{selection}` are stored in the origin and `{changes}` reads the file from disk.

When a draft exists, `on_new_payload` accepts `"ask"`, `"keep"`, `"replace"`, or `"append"`. The dialog selects **Keep Draft** by default. A non-empty `send()` call updates the session configuration, callbacks, and delivery options. This update also occurs when you keep the existing pages. A `send()` call without text only reopens a hidden draft.

Wiremux selects the compose value in this order:

1. The item-level `compose` value.
2. The call-level `opts.compose` value.
3. The `actions.send.compose` value.

Wiremux uses the first available value. It does not merge tables from these three levels. Wiremux merges the selected table with the session fields from `ui.compose`.

#### Customize compose when it opens

Wiremux emits the `User` event `WiremuxComposeOpen` after it configures and focuses a compose window. Use this event to start insert mode, enable spell checking, or add buffer-local mappings:

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

The event data contains `buf`, `win`, and `reopened`. For a new window, `reopened` is `false`. For a restored hidden window, `reopened` is `true`. Wiremux does not emit the event when it only focuses a visible window. Register the autocmd before you open compose.

### Send keystrokes before and after text

Some TUI applications require keystrokes before or after pasted text. For example, use `C-c` to cancel current input. Use `Escape` to return to a neutral state after Wiremux pastes the text:

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

Item-level `pre_keys` and `post_keys` values override call-level values.

## Placeholders

Wiremux replaces `{placeholders}` when it sends the text. Put each placeholder name in one pair of braces. The name must match `[A-Za-z_][A-Za-z0-9_]*`.

| Placeholder         | Replacement                                    |
| ------------------- | ---------------------------------------------- |
| `{file}`            | current buffer path                            |
| `{filename}`        | basename of `{file}`                           |
| `{position}`        | `file:line:col` (line and column start at 1)   |
| `{line}`            | current line text                              |
| `{selection}`       | visual selection (empty if not in visual mode) |
| `{this}`            | `{position}` plus `{selection}` when available |
| `{diagnostics}`     | diagnostics on current line                    |
| `{diagnostics_all}` | all diagnostics in current buffer              |
| `{quickfix}`        | formatted quickfix list                        |
| `{buffers}`         | list of listed, loaded buffers                 |
| `{changes}`         | `git diff HEAD -- {file}` (or "No changes")    |

Wiremux handles resolver results as follows:

| Resolver outcome  | Resulting text               |
| ----------------- | ---------------------------- |
| Non-empty string  | Replaces the placeholder     |
| Empty string `""` | Removes the placeholder text |
| `nil`             | Placeholder remains literal  |
| Resolver error    | Placeholder remains literal  |
| Non-string value  | Placeholder remains literal  |
| Unknown name      | Placeholder remains literal  |

Wiremux resolves each name one time for each send, and only for the item that you send. It does not resolve a placeholder before you choose a target, so a library of ten items that contains `{changes}` starts one `git diff` process instead of ten. Set `placeholders = false` on an item to send text such as `{file}` without replacement; that also keeps names literal if you add them in compose.

Wiremux captures the source origin one time for each `send()` call, before it opens a picker or a compose window. It then resolves the text of the item that you send. For compose drafts, Wiremux keeps the original text in each page and resolves each page against that page's origin when you confirm the draft.

You can add custom placeholders. A resolver name must start with a letter or underscore. The remaining characters must be letters, digits, or underscores:

```lua
require("wiremux").setup({
  context = {
    resolvers = {
      git_branch = function()
        local result = vim.system({ "git", "branch", "--show-current" }, { text = true }):wait()
        return result.code == 0 and vim.trim(result.stdout) or nil
      end,
      source_path = function(origin)
        return origin and origin.path or vim.api.nvim_buf_get_name(0)
      end,
    },
  },
})
```

Each `setup()` call replaces the previous set of custom resolvers. Built-in resolvers remain available. Keep each resolver fast. Do not change editor state from a resolver.

Wiremux calls a resolver with the origin of the text that it sends. The origin contains `bufnr`, `path`, `row`, `col`, `selection`, and `line`. The row starts at one. The column is a zero-based byte index. Wiremux passes a copy, so a resolver cannot change the stored origin.

Read the origin when a value must not change after the send starts. A zero-argument resolver still works, but it runs when Wiremux sends the text, so it reads the editor state at that moment. This difference matters only for a compose draft that stays open, because a direct send resolves immediately.

## Advanced configuration

### Target resolution options

When you run an action, Wiremux selects the targets to show. Use these four options to control the selection:

**1. Specific target:** Use a named target without a picker:

```lua
require("wiremux").send("{this}", { target = "claude" })
require("wiremux").focus({ target = "claude" })
```

Wiremux uses matching instances when they exist. If no instance matches, Wiremux creates one from the definition. Filters still apply. Wiremux cannot find a target that a filter excludes.

**2. Behavior:** Select how Wiremux handles multiple targets:

| Behavior | Result                  | Use it when                         |
| -------- | ----------------------- | ----------------------------------- |
| `pick`   | Shows the target picker | You select a target for each action |
| `last`   | Uses the latest target  | You repeat an action                |
| `all`    | Uses every target       | You send the text to all targets    |

**3. Mode:** Select where Wiremux looks for targets. This option applies only to `send()` and `toggle()`:

| Mode          | Result                            | Use it when                         |
| ------------- | --------------------------------- | ----------------------------------- |
| `auto`        | Shows instances, then definitions | You want the default selection      |
| `instances`   | Shows only existing instances     | You manage existing targets         |
| `definitions` | Shows only target definitions     | You want Wiremux to create a target |
| `all`         | Shows instances and definitions   | You want all available targets      |

**4. Filters:** Control which targets Wiremux shows:

By default, Wiremux shows only targets created from your current tmux pane. You can replace this filter:

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

### Complete configuration example

Use this example as a starting point for AI assistants, project commands, and target filters:

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
    -- Send motion (works like an operator: ga + motion; for example, gaip sends a paragraph)
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

## Actions and commands

Use Lua functions in keymaps and Lua code. Use Vim commands on the command line:

| Lua Function    | Vim Command            | What it does                              | Common use case                                            |
| --------------- | ---------------------- | ----------------------------------------- | ---------------------------------------------------------- |
| `send()`        | `:Wiremux send <text>` | Sends text to a target                    | Send code, prompts, or commands to an AI or terminal       |
| `send_motion()` | `:Wiremux send-motion` | Sends text covered by a motion (operator) | Works like `y`: map to `ga`, then `gaip` sends a paragraph |
| `create()`      | `:Wiremux create`      | Creates a new target from a definition    | Start a new AI assistant or terminal pane                  |
| `toggle()`      | `:Wiremux toggle`      | Shows or hides the last used target       | Show or hide an AI assistant or terminal                   |
| `focus()`       | `:Wiremux focus`       | Moves focus to a target                   | Move to your terminal or AI assistant                      |
| `close()`       | `:Wiremux close`       | Closes a target                           | Stop an AI assistant or terminal                           |
| `adopt()`       | `:Wiremux adopt`       | Makes Wiremux manage an existing pane     | Add an existing pane to Wiremux                            |

`send_motion()` sends captured source with `placeholders = false`, so placeholder-shaped code such as `{file}` remains literal.

### Adopt existing panes

Use `:Wiremux adopt` or `require("wiremux").adopt()` to make Wiremux manage an existing tmux pane. By default, the picker shows all panes in the current tmux session. It includes unmanaged panes but excludes the current pane.

Wiremux gives each unmanaged pane a generated target name, such as `pane-3`. Set `target` to use a specific target name:

```lua
require("wiremux").adopt({ target = "terminal" })
```

For a Lua call, `filter.instances` replaces the default adopt filter. Use this option to include panes from other sessions in the queried pane list:

```lua
require("wiremux").adopt({
  filter = {
    instances = function()
      return true -- all queried panes except the current pane
    end,
  },
})
```

Combine `target` with a filter to give matching panes a known target name:

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

Use `format_item` to change the rows in the adopt picker:

```lua
require("wiremux").adopt({
  format_item = function(pane)
    return string.format("%s %s %s", pane.target or "unmanaged", pane.id, pane.running_command or "")
  end,
})
```

**Tip:** Lua functions support placeholders, options, and dynamic content. Vim commands are useful on the command line and in Vimscript mappings.

## Statusline

Show the number of active Wiremux targets in your statusline.

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

Use `get_info()` to create a custom statusline component:

```lua
function()
  local info = require("wiremux").statusline.get_info()
  if info.count == 0 then return "" end
  local icon = info.last_used.kind == "window" and "󰖯" or "󰆍"
  return string.format("%s %d", icon, info.count)
end
```

Statusline API:

- `statusline.get_info()` returns `{ loading, count, last_used }`.
- `statusline.component()` returns a function for lualine.
- `statusline.refresh()` refreshes the statusline immediately.

## Persistence

Wiremux stores its state in tmux pane variables, not in Neovim. Targets remain available after you restart Neovim. Multiple Neovim instances can share the same targets.

## Troubleshooting

- Run `:checkhealth wiremux`
- Verify that Neovim runs inside tmux and that `$TMUX` is set

## Help

- `:h wiremux`

## Credits

- [folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) inspired the project and some implementation patterns.

Development included AI-assisted tools. The maintainers reviewed and adjusted all generated code.
