-- Pull in the wezterm API
local wezterm = require 'wezterm'

local msys2_path = "C:/msys64/"
local font_name = "JetBrains Mono"

-- This table will hold the configuration.
local config = {
}

-- In newer versions of wezterm, use the config_builder which will
-- help provide clearer error messages
if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- Uncomment this on virtual machine. More info https://github.com/wez/wezterm/issues/1813
-- config.prefer_egl = true

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_scheme = 'AdventureTime'

config.launch_menu = {
  {
    -- Optional label to show in the launcher. If omitted, a label
    -- is derived from the `args`
    label = 'nvim',
    -- The argument array to spawn.  If omitted the default program
    -- will be used as described in the documentation above
    args = { 'nvim' },

    -- You can specify an alternative current working directory;
    -- if you don't specify one then a default based on the OSC 7
    -- escape sequence will be used (see the Shell Integration
    -- docs), falling back to the home directory.
    -- cwd = "/some/path"

    -- You can override environment variables just for this command
    -- by setting this here.  It has the same semantics as the main
    -- set_environment_variables configuration option described above
    -- set_environment_variables = { FOO = "bar" },
  },
  {
    label = "UCRT64/MSYS2",
    args = { msys2_path.."msys2_shell.cmd", "-defterm", "-here", "-no-start", "-ucrt64", "-full-path"},
  },
  {
    label = "Fish",
    args = { msys2_path.."msys2_shell.cmd", "-defterm", "-here", "-no-start", "-ucrt64", "-shell", "fish"},
  },
  {
    label = "test",
    args = {"cmd.exe", "/k", "echo", "Hello"}
  },
}

config.font = wezterm.font(font_name, {weight = "Light"})
config.font_rules = {
  {
    intensity = "Bold",
    italic = false,
    font = wezterm.font(font_name, {weight = "Bold"}),
  },
}
config.font_size = 11

config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0
}

config.window_decorations = "RESIZE"
config.window_background_opacity = 0.8
config.scrollback_lines = 4000


wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():set_position(1720, 0)
  window:gui_window():set_inner_size(1720, 1350)
end)


-- and finally, return the configuration to wezterm
return config
