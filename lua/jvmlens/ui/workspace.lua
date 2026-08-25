-- The "debugger view": a dedicated tab, kept separate from whatever code
-- you're editing. Opening it remembers which tab you came from, so closing
-- it puts you back exactly where you were — that's the whole job of this
-- file, nothing more yet.
--
-- This is UI-only: it does not know or care what will eventually be shown
-- inside the debugger tab. Later steps will put real content (endpoint
-- list, code, variables) in the tab this file opens; for now it's just
-- the switch-in / switch-out mechanic, proven to work on its own first.

local M = {}

-- Tab handle (a number) of the debugger tab, or nil if it isn't open.
local debugger_tab = nil

-- Tab handle we were on before opening the debugger view, so M.close()
-- can put you back there.
local origin_tab = nil

function M.is_open()
  -- Tab numbers can be reused after a tab closes, so we check the handle
  -- we saved is still a real, valid tab before trusting it.
  return debugger_tab ~= nil and vim.api.nvim_tabpage_is_valid(debugger_tab)
end

function M.open()
  if M.is_open() then
    vim.api.nvim_set_current_tabpage(debugger_tab)
    return
  end

  origin_tab = vim.api.nvim_get_current_tabpage()

  vim.cmd("tabnew")
  debugger_tab = vim.api.nvim_get_current_tabpage()

  -- Placeholder content for now. Later steps replace this buffer's
  -- contents with the real debugger panels.
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    "  JVMLens debugger view",
    "",
    "  (nothing here yet — this is just the tab switch working)",
    "",
    "  press the same keybind again to go back",
  })
  vim.bo[buf].modifiable = false
end

function M.close()
  if not M.is_open() then
    return
  end

  vim.api.nvim_set_current_tabpage(debugger_tab)
  vim.cmd("tabclose")
  debugger_tab = nil

  if origin_tab and vim.api.nvim_tabpage_is_valid(origin_tab) then
    vim.api.nvim_set_current_tabpage(origin_tab)
  end
  origin_tab = nil
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

return M
