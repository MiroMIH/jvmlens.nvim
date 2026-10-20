-- Shows a read-only preview of a source file at a specific line, inside a
-- given window — with everything outside a given "focus" line range
-- dimmed out, so only the method that matters stands out (the same idea
-- as twilight.nvim, just scoped to a known method range instead of
-- guessing context).
--
-- This is a PREVIEW, not the real file buffer: it copies the file's text
-- into its own scratch buffer instead of opening the file for real. That
-- means the dimming (and anything else this does) can never bleed into a
-- window somewhere else where you have that same file open for editing.

local M = {}

local DIM_GROUP = "JVMLensDim"
local dim_ns = vim.api.nvim_create_namespace("jvmlens_code_dim")

local BREAKPOINT_GROUP = "JVMLensBreakpoint"
local breakpoint_ns = vim.api.nvim_create_namespace("jvmlens_code_breakpoint")

-- One scratch buffer, reused every time show() is called, so this
-- doesn't leak a new buffer every time you move the cursor in the list.
local preview_buf = nil

local function ensure_preview_buf()
  if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
    return preview_buf
  end
  preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].bufhidden = "hide"
  vim.bo[preview_buf].swapfile = false
  vim.bo[preview_buf].buflisted = false
  return preview_buf
end

local function ensure_dim_highlight()
  -- Comment is a low-contrast/grey group in most colorschemes, so linking
  -- to it gives a reasonable dim effect without hardcoding a color that
  -- might clash with whatever theme is active.
  vim.api.nvim_set_hl(0, DIM_GROUP, { link = "Comment", default = true })
end

local function ensure_breakpoint_highlight()
  vim.api.nvim_set_hl(0, BREAKPOINT_GROUP, { link = "DiagnosticError", default = true })
end

function M.open_right_split(left_win)
  vim.api.nvim_set_current_win(left_win)
  vim.cmd("belowright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  return win
end

-- Shows `file` at `line` (1-indexed) inside `win`. If `focus_start` and
-- `focus_end` (1-indexed, inclusive) are given, every line outside that
-- range is dimmed. If `breakpoint_line` (1-indexed) is given, that line
-- gets a red dot in the sign column — the "this is armed as a
-- breakpoint" indicator. The caller decides `breakpoint_line`: it's only
-- meaningful when the armed breakpoint's file matches `file`, so passing
-- nil here means "no breakpoint on this file."
function M.show(win, file, line, focus_start, focus_end, breakpoint_line)
  local buf = ensure_preview_buf()

  local lines = vim.fn.readfile(file)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Deliberately NOT setting `filetype` here. Setting it fires the same
  -- FileType autocmd that attaches the real language server — and jdtls
  -- attaching to a nameless scratch buffer is exactly what crashed the
  -- whole Java LSP session earlier (it can't resolve a file:// URI for a
  -- buffer with no path). Treesitter highlighting doesn't need filetype
  -- at all — attach it directly by language name instead.
  local lang = vim.filetype.match({ filename = file })
  if lang then
    pcall(vim.treesitter.start, buf, lang)
  end

  vim.api.nvim_win_set_buf(win, buf)

  local last_line = #lines
  if last_line > 0 then
    local target_line = math.min(line, last_line)
    vim.api.nvim_win_set_cursor(win, { target_line, 0 })
  end

  vim.api.nvim_buf_clear_namespace(buf, dim_ns, 0, -1)
  if focus_start and focus_end then
    ensure_dim_highlight()

    if focus_start > 1 then
      vim.api.nvim_buf_set_extmark(buf, dim_ns, 0, 0, {
        end_row = focus_start - 1,
        hl_group = DIM_GROUP,
        hl_eol = true,
      })
    end

    if focus_end < last_line then
      vim.api.nvim_buf_set_extmark(buf, dim_ns, focus_end, 0, {
        end_row = last_line,
        hl_group = DIM_GROUP,
        hl_eol = true,
      })
    end
  end

  vim.api.nvim_buf_clear_namespace(buf, breakpoint_ns, 0, -1)
  if breakpoint_line and breakpoint_line <= last_line then
    ensure_breakpoint_highlight()
    vim.api.nvim_buf_set_extmark(buf, breakpoint_ns, breakpoint_line - 1, 0, {
      sign_text = "●",
      sign_hl_group = BREAKPOINT_GROUP,
    })
  end
end

return M
