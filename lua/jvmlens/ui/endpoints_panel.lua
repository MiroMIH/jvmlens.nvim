-- Fills the debugger view's buffer with the project's Spring endpoints,
-- and drives a code-view panel to its right that shows whichever
-- endpoint's source the cursor is currently on. This file is glue: it
-- asks core/endpoints.lua what the endpoints are, and hands them to
-- ui/list.lua (the list) and ui/code_view.lua (the source panel) to draw.
-- It doesn't scan files or set buffer lines itself.
--
-- This is UI-only right now — no debugger wired in. The <CR>-to-arm-a-
-- breakpoint-and-attach behavior was removed along with nvim-dap; it'll
-- come back once jvmlens has its own debug client.

local endpoints = require("jvmlens.core.endpoints")
local list = require("jvmlens.ui.list")
local code_view = require("jvmlens.ui.code_view")

local M = {}

-- The endpoints that were last drawn, so a future step can look up
-- what's under the cursor.
M.last_scanned = {}

-- Width of the list panel on the left, in columns. The code view takes
-- whatever's left of the tab.
local LIST_WIDTH = 46

-- Spaces between columns.
local COLUMN_GAP = 2

-- The controller name is a muted grey, same idea as the code view's
-- dimming — a terminal can't render it in a smaller font (there's no
-- such thing as per-character font size in a terminal), but dimming it
-- gets the same "this matters less" effect.
local MUTED_GROUP = "JVMLensMuted"
local list_ns = vim.api.nvim_create_namespace("jvmlens_endpoint_list")

local function ensure_muted_highlight()
  vim.api.nvim_set_hl(0, MUTED_GROUP, { link = "Comment", default = true })
end

local function project_root(origin_buf)
  local ok, root = pcall(vim.fs.root, origin_buf, { "pom.xml", "build.gradle", "build.gradle.kts", ".git" })
  return (ok and root) or vim.fn.getcwd()
end

-- Each column is exactly as wide as its longest actual value across all
-- rows, so the list lines up like a real table instead of using guessed
-- fixed widths that go ragged once something's longer than expected.
local function compute_column_widths(found)
  local verb_w, path_w = 0, 0
  for _, ep in ipairs(found) do
    verb_w = math.max(verb_w, #ep.verb)
    path_w = math.max(path_w, #ep.path)
  end
  return verb_w, path_w
end

local function make_formatter(verb_w, path_w)
  local fmt = "%-" .. verb_w .. "s" .. string.rep(" ", COLUMN_GAP) .. "%-" .. path_w .. "s" .. string.rep(" ", COLUMN_GAP) .. "%s"
  return function(ep)
    return string.format(fmt, ep.verb, ep.path, ep.class_name or "")
  end
end

-- Dims the controller-name column (everything from `class_col` to the
-- end of each line) so it recedes without needing font-size tricks a
-- terminal can't do anyway.
local function mute_class_name_column(buf, class_col)
  ensure_muted_highlight()
  vim.api.nvim_buf_clear_namespace(buf, list_ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if #line > class_col then
      vim.api.nvim_buf_set_extmark(buf, list_ns, i - 1, class_col, {
        end_row = i - 1,
        end_col = #line,
        hl_group = MUTED_GROUP,
      })
    end
  end
end

-- Matches ui/workspace.lua's `on_open(buf, origin_buf)` signature — this
-- is meant to be passed straight to workspace.open()/toggle().
function M.render(buf, origin_buf)
  local root = project_root(origin_buf)
  local found = endpoints.scan(root)
  M.last_scanned = found

  if #found == 0 then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "",
      "  No Spring endpoints found under:",
      "  " .. root,
    })
    vim.bo[buf].modifiable = false
    return
  end

  local verb_w, path_w = compute_column_widths(found)
  list.render(buf, found, make_formatter(verb_w, path_w))
  mute_class_name_column(buf, verb_w + COLUMN_GAP + path_w + COLUMN_GAP)

  local list_win = vim.api.nvim_get_current_win()

  -- The vsplit below resets window widths to a 50/50 split, so the list
  -- has to be narrowed *after* it exists, not before.
  local right_win = code_view.open_right_split(list_win)
  vim.api.nvim_win_set_width(list_win, LIST_WIDTH)
  code_view.show(right_win, found[1].file, found[1].line, found[1].method_start_line, found[1].method_end_line)

  -- Put focus back on the list so you can move up/down it right away.
  vim.api.nvim_set_current_win(list_win)

  -- Buffer-scoped autocmds are removed automatically when the buffer is
  -- wiped (which ui/workspace.lua already does on close), so there's
  -- nothing to clean up by hand here.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      local ep = list.selected(list_win, found)
      if ep then
        code_view.show(right_win, ep.file, ep.line, ep.method_start_line, ep.method_end_line)
      end
    end,
  })
end

return M
