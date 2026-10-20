-- Public entry point. Everything user-facing (setup, keymaps, commands)
-- starts here. This file has no logic of its own — it just wires config
-- and ui together. If you're looking for where a feature actually lives,
-- it's not in this file; follow the require() calls.

local M = {}

function M.setup(user_opts)
  local config = require("jvmlens.config")
  config.setup(user_opts)

  local workspace = require("jvmlens.ui.workspace")
  local endpoints_panel = require("jvmlens.ui.endpoints_panel")

  vim.keymap.set("n", config.options.keymaps.toggle_view, function()
    workspace.toggle(endpoints_panel.render)
  end, {
    desc = "JVMLens: toggle debugger view",
  })
end

return M
