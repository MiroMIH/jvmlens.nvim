-- The "debugger view": a dedicated tab, kept separate from whatever code
-- you're editing. Opening it remembers which tab you came from, so closing
-- it puts you back exactly where you were.
--
-- This file only manages the tab itself (open/close/toggle) and generic
-- window settings for it. It does NOT know what goes inside — the caller
-- passes an `on_open(buf, origin_buf)` function that fills the buffer once
-- the tab exists. `origin_buf` is the buffer you were on before switching,
-- passed through so the caller can figure out things like "which project
-- is this" from wherever you actually were.

local M = {}

-- Tab handle (a number) of the debugger tab, or nil if it isn't open.
local debugger_tab = nil

-- Tab handle we were on before opening the debugger view, so M.close()
-- can put you back there.
local origin_tab = nil

-- The list buffer created for the current debugger-view session, so
-- M.close() can explicitly delete it (see bufhidden note below).
local debugger_buf = nil

function M.is_open()
  -- Tab numbers can be reused after a tab closes, so we check the handle
  -- we saved is still a real, valid tab before trusting it.
  return debugger_tab ~= nil and vim.api.nvim_tabpage_is_valid(debugger_tab)
end

-- `on_open(buf, origin_buf)` is optional — if omitted, a small default
-- placeholder is shown instead.
function M.open(on_open)
  if M.is_open() then
    vim.api.nvim_set_current_tabpage(debugger_tab)
    return
  end

  origin_tab = vim.api.nvim_get_current_tabpage()
  local origin_buf = vim.api.nvim_get_current_buf()

  vim.cmd("tabnew")
  debugger_tab = vim.api.nvim_get_current_tabpage()

  local buf = vim.api.nvim_get_current_buf()
  debugger_buf = buf
  vim.bo[buf].buftype = "nofile"
  -- NOT "wipe": something else (like nvim-dap's own jump-to-frame) can
  -- swap this window to a different buffer at any time, and "wipe" would
  -- auto-delete this buffer the instant no window shows it anymore —
  -- which happened live and made it impossible to reclaim the window
  -- afterward. "hide" keeps it alive regardless; M.close() deletes it
  -- explicitly instead, once we're actually done with it.
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  -- :tabnew's starting buffer is "listed" by default, which is why it was
  -- showing up in the bufferline next to whatever file you had open.
  vim.bo[buf].buflisted = false

  -- This is a tool view, not a code view — no line numbers.
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.cursorline = true

  if on_open then
    on_open(buf, origin_buf)
  else
    vim.bo[buf].modifiable = true
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
end

function M.close()
  if not M.is_open() then
    return
  end

  vim.api.nvim_set_current_tabpage(debugger_tab)
  vim.cmd("tabclose")
  debugger_tab = nil

  if debugger_buf and vim.api.nvim_buf_is_valid(debugger_buf) then
    vim.api.nvim_buf_delete(debugger_buf, { force = true })
  end
  debugger_buf = nil

  if origin_tab and vim.api.nvim_tabpage_is_valid(origin_tab) then
    vim.api.nvim_set_current_tabpage(origin_tab)
  end
  origin_tab = nil
end

function M.toggle(on_open)
  if M.is_open() then
    M.close()
  else
    M.open(on_open)
  end
end

return M
