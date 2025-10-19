# workspace-picker.wez

A comprehensive workspace switcher plugin for [WezTerm](https://wezfurlong.org/wezterm/) that integrates with static workspace configurations, Git worktrees, Zoxide directory tracking, and existing WezTerm workspaces.

## Features

- 🔍 **Fuzzy Search**: Quickly find and switch between workspaces
- 📁 **Directory Integration**: Direct navigation to configured directories
- 🌳 **Git Worktree Support**: Automatic discovery of Git worktrees
- ⚡ **Zoxide Integration**: Access frequently visited directories
- 🖥️ **Existing Workspace Support**: Switch between active WezTerm workspaces
- 🎨 **Custom Pane Layouts**: Define complex tab and pane configurations
- ⌨️ **Keyboard Shortcuts**: Bind to custom key combinations

## Installation

### Via luarocks (recommended)

```bash
luarocks install workspace-picker
```

### Manual Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/workspace-picker.git
   ```

2. Copy the module to your WezTerm configuration:
   ```bash
   cp workspace-picker/lib/workspace-picker.lua ~/.config/wezterm/
   ```

## Usage

### Basic Setup

Add to your `wezterm.lua`:

```lua
local workspace_picker = require("workspace-picker")

-- Configure workspaces
workspace_picker.setup({
  { path = "~/projects/my-project", type = "directory" },
  { path = "~/projects/worktrees", type = "worktreeroot" },
})

-- Apply default keybinding (LEADER + f)
workspace_picker.apply_to_config(config)
```

### Advanced Configuration

```lua
local workspace_picker = require("workspace-picker")

workspace_picker.setup({
  -- Static directory
  {
    path = "~/dotfiles",
    tabs = {
      { name = "editor", panes = { { command = "vim" } } },
      { name = "terminal" },
    }
  },

  -- Git worktree root
  {
    path = "~/Projects/my-repo.git",
    type = "worktreeroot",
    tabs = {
      {
        name = "development",
        direction = "Bottom",
        panes = {
          { command = "vim" },
          {
            direction = "Right",
            panes = {
              { command = "npm run dev" },
              { command = "npm run test" }
            }
          }
        }
      }
    }
  }
}, {
  icons = {
    directory = "📁",
    worktree = "🌳",
    zoxide = "⚡",
    workspace = "🖥️",
  }
})

-- Apply to config with custom keybinding
workspace_picker.apply_to_config(config, "w", "CTRL|SHIFT")
```

### Direct Workspace Switching

```lua
-- Direct keybindings for specific workspaces
config.keys = {
  {
    key = "n",
    mods = "LEADER",
    action = workspace_picker.switch_to_workspace("~/Notes")
  },
  {
    key = "d",
    mods = "LEADER",
    action = workspace_picker.switch_to_workspace("~/dotfiles")
  }
}
```

## Configuration Options

### Workspace Entry

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | string | Yes | Path to directory or worktree root |
| `type` | string | No | `"directory"` or `"worktreeroot"` (default: `"directory"`) |
| `tabs` | table | No | Array of tab configurations |

### Tab Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | No | Tab title |
| `direction` | string | No | Split direction: `"Right"` or `"Bottom"` (default: `"Right"`) |
| `panes` | table | No | Array of pane configurations |

### Pane Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | No | Pane name (for identification) |
| `command` | string | No | Command to run in pane |
| `direction` | string | No | Split direction for child panes |
| `panes` | table | No | Child pane configurations |

### Plugin Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `icons.directory` | string | `""` | Icon for directory workspaces |
| `icons.worktree` | string | `"󰊢"` | Icon for worktree workspaces |
| `icons.zoxide` | string | `""` | Icon for zoxide workspaces |
| `icons.workspace` | string | `""` | Icon for existing workspaces |

## Requirements

- WezTerm
- Git (for worktree support)
- Zoxide (optional, for directory tracking)

## License

MIT