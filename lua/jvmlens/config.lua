-- Every option and its default value lives here, and only here. No other
-- file in the plugin should hardcode a default or read vim.g directly —
-- if a piece of behavior needs to be configurable, it reads
-- require("jvmlens.config").options.

local M = {}

M.defaults = {
  keymaps = {
    -- Switch into / out of the debugger view.
    toggle_view = "<leader>lv",
  },
}

-- Filled in by setup(). Everything else reads this table after setup()
-- has run — never M.defaults directly.
M.options = {}

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, user_opts or {})
end

return M
