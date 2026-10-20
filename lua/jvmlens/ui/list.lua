-- A generic "show a list of things in a buffer" building block. Nothing
-- in here knows what an endpoint, a stop, or anything else is — it only
-- knows how to turn a plain Lua list into buffer lines, and how to read
-- back which item the cursor is on. Every future list-style panel should
-- reuse this instead of writing its own buffer-line code.

local M = {}

-- Renders `items` into `buf`, one line per item, using
-- `format_fn(item) -> string` to turn each item into its display line.
function M.render(buf, items, format_fn)
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, format_fn(item))
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

-- Returns the item under the cursor in `win`, given the same `items` list
-- that was passed to render(). Returns nil if the list is empty or the
-- cursor is somehow past the end (defensive — this is exactly the kind
-- of bounds check that's easy to forget when written ad hoc per feature).
function M.selected(win, items)
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return items[row]
end

return M
