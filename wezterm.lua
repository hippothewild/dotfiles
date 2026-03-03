local wezterm = require "wezterm"
local config = wezterm.config_builder()
local action = wezterm.action

-- Render using WebGPU
config.front_end = 'WebGpu'

-- Font configuration
config.font = wezterm.font {
  family = 'Hack',
  weight = 'Regular',
  harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' },
}
config.font_size = 22.0
config.line_height = 1.15
config.cell_width = 0.9

-- Color scheme
config.colors = {
  foreground = "#c5c8c6",
  background = "#1d1f21",

  -- ANSI Colors
  ansi = {
    "#000000",  -- Black (Ansi 0)
    "#cc6666",  -- Red (Ansi 1)
    "#b5bd68",  -- Green (Ansi 2)
    "#f0c674",  -- Yellow (Ansi 3)
    "#81a2be",  -- Blue (Ansi 4)
    "#b294bb",  -- Magenta (Ansi 5)
    "#8abeb7",  -- Cyan (Ansi 6)
    "#ffffff",  -- White (Ansi 7)
  },

  -- Bright ANSI Colors
  brights = {
    "#000000",  -- Bright Black (Ansi 8)
    "#cc6666",  -- Bright Red (Ansi 9)
    "#b5bd68",  -- Bright Green (Ansi 10)
    "#f0c674",  -- Bright Yellow (Ansi 11)
    "#81a2be",  -- Bright Blue (Ansi 12)
    "#b294bb",  -- Bright Magenta (Ansi 13)
    "#8abeb7",  -- Bright Cyan (Ansi 14)
    "#ffffff",  -- Bright White (Ansi 15)
  },

  -- UI Colors
  cursor_bg = "#c5c8c6",
  cursor_fg = "#1d1f21",
  selection_bg = "#373b41",
  selection_fg = "#c5c8c6",
}

-- Window configuration
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.window_background_opacity = 0.92
config.window_padding = { left = '0.5cell', right = '0.5cell', top = '0.5cell', bottom = '0.5cell' }
config.default_cursor_style = 'SteadyBlock'

-- Terminal configuration
config.scrollback_lines = 50000
config.enable_scroll_bar = true
config.enable_tab_bar = true
config.use_fancy_tab_bar = true

-- Key bindings
config.keys = {
  -- Maximize window while keeping decorations

  -- Split panes
  {mods = 'CMD', key = 'm', action = action.SplitVertical{domain = 'CurrentPaneDomain'}},
  {mods = 'CMD', key = 'l', action = action.SplitHorizontal{domain = 'CurrentPaneDomain'}},

  -- Navigate between panes
  {mods = 'CMD', key = '[', action = action.ActivatePaneDirection('Prev')},
  {mods = 'CMD', key = ']', action = action.ActivatePaneDirection('Next')},

  -- Line navigation (Command + Arrow)
  { mods = 'CMD', key = 'LeftArrow', action = action.SendKey { key = 'Home' } },
  { mods = 'CMD', key = 'RightArrow', action = action.SendKey { key = 'End' } },

  -- Word-by-word navigation (Option + Arrow)
  { mods = 'ALT', key = 'LeftArrow', action = action.SendKey { mods = 'ALT', key = 'b' } },
  { mods = 'ALT', key = 'RightArrow', action = action.SendKey { mods = 'ALT', key = 'f' } },

  -- Word-by-word deletion
  { mods = 'ALT', key = 'Backspace', action = action.SendKey { mods = 'ALT', key = 'Backspace' } },
}

-- Tab title: show current directory name instead of process name
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local cwd = pane.current_working_dir
  local title = pane.title
  local is_shell = title:match("^zsh$") or title:match("^bash$") or title:match("^fish$") or title:match("^sh$")
  local idx = tab.tab_index + 1
  if cwd then
    local cwd_path = cwd.file_path or ""
    local folder = cwd_path:match("([^/]+)/?$") or "~"
    if is_shell then
      return { { Text = " " .. idx .. ": " .. folder .. " " } }
    end
    return { { Text = " " .. idx .. ": " .. folder .. " | " .. title .. " " } }
  end
  return { { Text = " " .. idx .. ": " .. title .. " " } }
end)

-- Status bar
config.status_update_interval = 2000
config.show_tabs_in_tab_bar = true
config.show_new_tab_button_in_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false

-- Helper: pick color by usage percentage threshold
local function usage_color(pct, low_color)
  if pct >= 80 then return "#f7768e"
  elseif pct >= 50 then return "#ff9e64"
  else return low_color
  end
end

-- Lua-level cache for Claude usage (refresh every 5 minutes)
local usage_cache = { session = nil, weekly = nil, last_fetch = 0 }

wezterm.on("update-status", function(window, pane)
  local home = os.getenv("HOME") or ""

  -- Get CPU usage
  local success_cpu, stdout_cpu, _ = wezterm.run_child_process({"/bin/sh", "-c", "top -l 1 | grep -E '^CPU' | awk '{print $3}'"})
  local cpu = success_cpu and stdout_cpu:gsub("%s+", "") or "N/A"

  -- Get memory pressure (percentage)
  local success_mem, stdout_mem, _ = wezterm.run_child_process({"/bin/sh", "-c", "echo $((100 - $(sysctl -n kern.memorystatus_level)))"})
  local memory = success_mem and stdout_mem:gsub("%s+", "") .. "%" or "N/A"

  -- Get Claude usage limits (Lua cache: 5 min, script cache: 60s)
  local now = os.time()
  if now - usage_cache.last_fetch > 300 then
    local usage_cmd = home .. "/.config/wezterm/claude-usage-cache.sh 2>/dev/null"
    local success_usage, stdout_usage, _ = wezterm.run_child_process({"/bin/sh", "-l", "-c", usage_cmd})
    if success_usage and stdout_usage and stdout_usage ~= "" then
      local s_pct = stdout_usage:match('"five_hour":%s*{%s*"utilization":%s*([%d%.]+)')
      local w_pct = stdout_usage:match('"seven_day":%s*{%s*"utilization":%s*([%d%.]+)')
      usage_cache.session = tonumber(s_pct)
      usage_cache.weekly = tonumber(w_pct)
    end
    usage_cache.last_fetch = now
  end

  -- Build status bar
  local status = {}

  table.insert(status, {Foreground = {Color = "#ff9e64"}})
  table.insert(status, {Text = "CPU: " .. cpu .. "    "})

  table.insert(status, {Foreground = {Color = "#9ece6a"}})
  table.insert(status, {Text = "Mem: " .. memory .. "    "})

  if usage_cache.session then
    table.insert(status, {Foreground = {Color = usage_color(usage_cache.session, "#bb9af7")}})
    table.insert(status, {Text = "Session: " .. string.format("%.0f", usage_cache.session) .. "%    "})
  end

  if usage_cache.weekly then
    table.insert(status, {Foreground = {Color = usage_color(usage_cache.weekly, "#7aa2f7")}})
    table.insert(status, {Text = "Weekly: " .. string.format("%.0f", usage_cache.weekly) .. "%    "})
  end

  window:set_right_status(wezterm.format(status))
end)

-- Additional configurations
config.adjust_window_size_when_changing_font_size = false  -- Do not resize window when changing font size
config.native_macos_fullscreen_mode = true                 -- Use MacOS native fullscreen mode

return config
