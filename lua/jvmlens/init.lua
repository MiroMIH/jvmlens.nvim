-- Public entry point. Everything user-facing (setup, keymaps, commands)
-- starts here. This file has no logic of its own — it just wires config
-- and ui together. If you're looking for where a feature actually lives,
-- it's not in this file; follow the require() calls.

local M = {}

function M.setup(user_opts)
  local config = require("jvmlens.config")
  config.setup(user_opts)

  local workspace = require("jvmlens.ui.workspace")

  vim.keymap.set("n", config.options.keymaps.toggle_view, workspace.toggle, {
    desc = "JVMLens: toggle debugger view",
  })
end

return M
