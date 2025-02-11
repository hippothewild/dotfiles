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
config.scrollback_lines = 10000
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

  -- Word-by-word navigation
  { mods = 'CMD', key = 'LeftArrow', action = action.SendKey { mods = 'ALT', key = 'b' } },
  { mods = 'CMD', key = 'RightArrow', action = action.SendKey { mods = 'ALT', key = 'f' } },
}

-- Status bar
config.status_update_interval = 2000
config.show_tabs_in_tab_bar = true
config.show_new_tab_button_in_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false

wezterm.on("update-status", function(window, pane)
  -- Get current date/time
  local date = wezterm.strftime("%a %b %-d %H:%M")

  -- Get CPU usage
  local success_cpu, stdout_cpu, stderr_cpu = wezterm.run_child_process({"sh", "-c", "top -l 1 | grep -E '^CPU' | awk '{print $3}'"})
  local cpu = success_cpu and stdout_cpu:gsub("\n", "") or "N/A"

  -- Get memory usage
  local success_mem, stdout_mem, stderr_mem = wezterm.run_child_process({"sh", "-c", "top -l 1 | grep -E '^PhysMem' | awk '{print $2}'"})
  local memory = success_mem and stdout_mem:gsub("\n", "") or "N/A"

  -- Set status bar text with colors
  window:set_right_status(wezterm.format({
    {Foreground = {Color = "#ff9e64"}},
    {Text = "CPU: " .. cpu .. "     "},
    {Foreground = {Color = "#9ece6a"}},
    {Text = "MEM: " .. memory .. "     "},
    {Foreground = {Color = "#7aa2f7"}},
    {Text = date .. "       "},
  }))
end)

-- Additional configurations
config.adjust_window_size_when_changing_font_size = false  -- Do not resize window when changing font size
config.native_macos_fullscreen_mode = true                 -- Use MacOS native fullscreen mode

return config
