local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local M = {}

--- Platform detection
local is_windows = string.find(wezterm.target_triple, "windows") ~= nil

--- User configuration storage
local user_config = {}

--- Default configuration options
local default_options = {
  --- Default icons for different workspace types
  icons = {
    directory = "📁",
    worktree = "🌳",
    zoxide = "⚡",
    workspace = "🖥️",
  },
}

--- Current options (merged with defaults)
local options = {}

--- Expand tilde (~) in paths to home directory
--- @param path string: Path that may contain ~
--- @return string|nil: Expanded path or nil if home directory cannot be determined
--- @return string|nil: Error message if expansion fails
local function expand_home_path(path)
  if not path or type(path) ~= "string" then return nil, "Invalid path: expected string" end

  if path:sub(1, 1) == "~" then
    local home = wezterm.home_dir
    if not home then return nil, "Unable to determine home directory" end
    path = home .. path:sub(2)
  end
  return path, nil
end

--- Run shell command and return output with proper error handling
--- @param cmd string: Command to execute
--- @return string: Command output (empty string on error)
--- @return string|nil: Error message if command failed
local function run_command(cmd)
  if not cmd or type(cmd) ~= "string" then return "", "Invalid command: expected string" end

  local args = { os.getenv("SHELL"), "-c", cmd }
  if is_windows then args = { "cmd", "/c", cmd } end

  local ok, stdout, stderr = wezterm.run_child_process(args)
  if not ok then
    local error_msg = string.format("Failed to run '%s': %s", cmd, stderr or "unknown error")
    wezterm.log_error(error_msg)
    return "", error_msg
  end

  return stdout or "", nil
end

--- Create a formatted label for a workspace entry
--- @param path string: Path to format
--- @param icon string: Icon to use
--- @return table: WezTerm formatted text
local function format_workspace_label(path, icon)
  local display_path = path:gsub(wezterm.home_dir or "", "~")
  return wezterm.format({ { Text = icon .. "  " .. display_path } })
end

--- Get static and worktree-based workspace entries from user configuration
--- @return table: List of workspace entries
local function get_config_entries()
  local entries = {}

  for _, entry in ipairs(user_config) do
    if entry.type == "worktreeroot" then
      -- Handle git worktree root
      local expanded_path, err = expand_home_path(entry.path)
      if not expanded_path then
        wezterm.log_error("Failed to expand worktree path '" .. entry.path .. "': " .. (err or "unknown error"))
      else
        local output, cmd_err = run_command("git -C " .. expanded_path .. " worktree list --porcelain")
        if cmd_err then
          wezterm.log_error("Failed to get worktrees for '" .. expanded_path .. "': " .. cmd_err)
        else
          for line in output:gmatch("[^\r\n]+") do
            if line:match("^worktree ") then
              local worktree_path = line:match("^worktree (.+)$")
              if worktree_path then
                table.insert(entries, {
                  id = worktree_path,
                  label = format_workspace_label(worktree_path, options.icons.worktree),
                  type = "worktree",
                  tabs = entry.tabs,
                })
              end
            end
          end
        end
      end
    elseif entry.path then
      -- Handle static directory entry
      local expanded_path, err = expand_home_path(entry.path)
      if not expanded_path then
        wezterm.log_error("Failed to expand path '" .. entry.path .. "': " .. (err or "unknown error"))
      else
        table.insert(entries, {
          id = expanded_path,
          label = format_workspace_label(expanded_path, options.icons.directory),
          type = "directory",
          tabs = entry.tabs,
        })
      end
    end
  end

  return entries
end

--- Get zoxide-tracked directory sessions
--- @return table: List of zoxide workspace entries
local function get_zoxide_sessions()
  local sessions = {}
  local output, err = run_command("zoxide query -l")

  if err then
    wezterm.log_warn("Zoxide not available or failed: " .. err)
    return sessions
  end

  for line in output:gmatch("[^\r\n]+") do
    if line and line ~= "" then
      table.insert(sessions, {
        id = line,
        label = format_workspace_label(line, options.icons.zoxide),
        type = "zoxide",
        tabs = nil,
      })
    end
  end

  return sessions
end

--- Get existing WezTerm workspace names
--- @return table: List of existing workspace entries
local function get_existing_workspaces()
  local workspaces = {}
  local names = mux.get_workspace_names()

  for _, name in ipairs(names or {}) do
    table.insert(workspaces, {
      id = name,
      label = format_workspace_label(name, options.icons.workspace),
      type = "workspace",
      tabs = nil,
    })
  end

  return workspaces
end

--- Get all available workspace choices, deduplicating by ID
--- @return table: Array of workspace choice objects
local function get_all_workspace_choices()
  local all_items = {}
  local seen_ids = {} -- Track seen IDs to avoid duplicates

  --- Add items to the list, skipping duplicates
  --- @param items table: Array of workspace items to add
  local function add_unique_items(items)
    for _, item in ipairs(items or {}) do
      if item.id and not seen_ids[item.id] then
        table.insert(all_items, item)
        seen_ids[item.id] = true
      end
    end
  end

  -- Add items in priority order (existing workspaces first, then configured, then zoxide)
  add_unique_items(get_existing_workspaces())
  add_unique_items(get_config_entries())
  add_unique_items(get_zoxide_sessions())

  return all_items
end

--- Generate split fractions for pane layout
--- @param n number: Number of panes to split
--- @return table: Array of fraction values for splits
local function generate_split_fractions(n)
  if n < 2 then return {} end

  local fractions = {}
  for i = 2, n do
    -- Insert at beginning to maintain correct order
    table.insert(fractions, 1, (i - 1) / i)
  end
  return fractions
end

--- Recursively create pane splits based on configuration
--- @param mux_pane table: WezTerm mux pane object
--- @param node table: Pane configuration node
local function create_pane_splits(mux_pane, node)
  -- Base case: leaf node with optional command
  if not node or not node.panes or #node.panes == 0 then
    if node and node.command then mux_pane:send_text(node.command .. "\r") end
    return
  end

  -- Validate node structure
  if not node.panes or type(node.panes) ~= "table" then
    wezterm.log_error("Invalid pane configuration: 'panes' must be a table")
    return
  end

  local fractions = generate_split_fractions(#node.panes)
  local current_pane = mux_pane

  for i, pane_config in ipairs(node.panes) do
    if i > 1 then
      -- Create split for additional panes
      local direction = node.direction or "Right"
      local size = fractions[i - 1]

      current_pane = current_pane:split({
        direction = direction,
        size = size,
      })

      if not current_pane then
        wezterm.log_error("Failed to create pane split")
        return
      end
    end

    -- Recursively process child panes
    create_pane_splits(current_pane, pane_config)
  end
end

--- Create tabs with their pane configurations
--- @param window table: WezTerm window object
--- @param tabs table: Array of tab configurations
local function create_tabs_with_panes(window, tabs)
  if not window then
    wezterm.log_error("Window is nil in create_tabs_with_panes")
    return
  end

  if not tabs or type(tabs) ~= "table" then
    wezterm.log_error("Invalid tabs configuration: expected table")
    return
  end

  for i, tab_config in ipairs(tabs) do
    if i > 1 then
      -- Create additional tabs
      window:spawn_tab({ title = tab_config.name })
    end

    -- Get the first pane of the current tab
    local window_tabs = window:tabs()
    if not window_tabs or not window_tabs[i] then
      wezterm.log_error("Failed to access tab " .. i)
      return
    end

    local tab = window_tabs[i]
    local panes = tab:panes()
    if not panes or not panes[1] then
      wezterm.log_error("Failed to access first pane of tab " .. i)
      return
    end

    local first_pane = panes[1]
    create_pane_splits(first_pane, tab_config)
  end
end

--- Create or switch to a workspace with proper configuration
--- @param item table: Workspace item with id, type, and tabs
--- @param window table: WezTerm window object
--- @param pane table: WezTerm pane object
local function create_or_switch_workspace(item, window, pane)
  if item.type == "workspace" then
    -- just switch in case already existing workspace
    window:perform_action(
      act.SwitchToWorkspace({
        name = item.id,
      }),
      pane
    )
  else
    -- For new workspaces (not existing ones), create the window first
    local cwd, err = expand_home_path(item.id)
    if err then
      wezterm.log_error("Failed to expand workspace path '" .. item.id .. "': " .. err)
      cwd = item.id -- fallback to original path
    end

    local _, _, new_window = mux.spawn_window({
      workspace = item.id,
      cwd = cwd,
    })

    if not new_window then
      wezterm.log_error("Failed to create workspace window for '" .. item.id .. "'")
      return
    end

    -- Switch to the workspace
    -- NOTE: has to be done before creating panes due to sizing information i guess
    window:perform_action(
      act.SwitchToWorkspace({
        name = item.id,
        spawn = {
          cwd = expand_home_path(item.id),
        },
      }),
      pane
    )

    -- Create tabs and panes if configured
    if item.tabs and #item.tabs > 0 then create_tabs_with_panes(new_window, item.tabs) end
  end
end

--- Switch to or create a workspace by name or path
--- @param path string: Workspace name or path to switch to
--- @return table: WezTerm action callback
function M.switch_to_workspace(path)
  return wezterm.action_callback(function(window, pane)
    print("here")
    local expanded_path = expand_home_path(path)

    -- Look for configured workspace
    local all_choices = get_all_workspace_choices()
    print(all_choices)
    for _, choice in ipairs(all_choices) do
      if choice.id == expanded_path then
        create_or_switch_workspace(choice, window, pane)
        return
      end
    end
  end)
end

--- Create the workspace switcher action
--- @return table: WezTerm action callback
local function switch_workspace_action()
  return wezterm.action_callback(function(window, pane)
    local choices = get_all_workspace_choices()

    -- Convert to input selector format
    local selector_choices = {}
    for _, choice in ipairs(choices) do
      table.insert(selector_choices, {
        id = choice.id,
        label = choice.label,
      })
    end

    window:perform_action(
      act.InputSelector({
        title = "Select Workspace",
        choices = selector_choices,
        fuzzy = true,
        action = wezterm.action_callback(function(win, p, id)
          if not id then return end

          -- Find the selected item
          local selected_item = nil
          for _, choice in ipairs(choices) do
            if choice.id == id then
              selected_item = choice
              break
            end
          end

          if not selected_item then
            wezterm.log_error("Selected workspace not found: " .. id)
            return
          end

          create_or_switch_workspace(selected_item, win, p)
        end),
      }),
      pane
    )
  end)
end

--- Validate a single workspace configuration entry
--- @param entry table: Configuration entry to validate
--- @return boolean: True if valid
--- @return string|nil: Error message if invalid
local function validate_config_entry(entry)
  if type(entry) ~= "table" then return false, "Configuration entry must be a table" end

  if not entry.path then return false, "'path' is required for each workspace entry" end

  if entry.type and entry.type ~= "directory" and entry.type ~= "worktreeroot" then
    return false, "Invalid type '" .. entry.type .. "'. Must be 'directory' or 'worktreeroot'"
  end

  if entry.tabs and type(entry.tabs) ~= "table" then return false, "'tabs' must be a table if provided" end

  return true, nil
end

--- Setup the workspace picker with user configuration
--- @param config table: User configuration table
--- @param opts table|nil: Additional options to override defaults
function M.setup(config, opts)
  -- Merge options with defaults
  options = {}
  for k, v in pairs(default_options) do
    options[k] = v
  end
  if opts then
    for k, v in pairs(opts) do
      options[k] = v
    end
  end

  -- Validate and process configuration
  user_config = {}
  if config and type(config) == "table" then
    for i, entry in ipairs(config) do
      local is_valid, error_msg = validate_config_entry(entry)
      if not is_valid then
        wezterm.log_error(string.format("Configuration entry %d: %s", i, error_msg))
      else
        -- Set default type if not specified
        if not entry.type then entry.type = "directory" end

        -- Ensure tabs is a table
        if not entry.tabs then entry.tabs = {} end

        table.insert(user_config, entry)
      end
    end
  end
end

--- Apply default keybindings to WezTerm configuration
--- @param config table: WezTerm configuration table
--- @param key string|nil: Key to bind (default: "f")
--- @param mods string|nil: Modifiers for keybinding (default: "LEADER")
function M.apply_to_config(config, key, mods)
  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = key or "f",
    mods = mods or "LEADER",
    action = switch_workspace_action(),
  })
end

return M
