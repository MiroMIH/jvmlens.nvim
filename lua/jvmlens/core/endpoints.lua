-- Finds every Spring HTTP endpoint in a project by reading the source
-- files directly (Treesitter) — no running JVM needed. This file only
-- produces data (a plain Lua list of endpoint tables); it never touches a
-- window or buffer for display, so it can be read/tested without running
-- any UI code.
--
-- An "endpoint" is: { verb, path, file, line, class_name, method_name }

local M = {}

local MAPPING_VERBS = {
  GetMapping = "GET",
  PostMapping = "POST",
  PutMapping = "PUT",
  DeleteMapping = "DELETE",
  PatchMapping = "PATCH",
}

local REQUEST_METHOD_VERB = { GET = true, POST = true, PUT = true, DELETE = true, PATCH = true }

local function strip_quotes(s)
  if not s then
    return nil
  end
  return (s:gsub('^"(.*)"$', "%1"))
end

-- Depth-first search for the first string literal under `node` — used to
-- pull a path out of an annotation regardless of how it's written
-- (`@GetMapping("/x")` vs `@GetMapping(value = "/x")` vs an array).
local function find_first_string_literal(node, source)
  if node:type() == "string_literal" then
    return strip_quotes(vim.treesitter.get_node_text(node, source))
  end
  for child in node:iter_children() do
    local found = find_first_string_literal(child, source)
    if found then
      return found
    end
  end
  return nil
end

-- Looks for `key = value` inside an annotation's argument list and
-- returns the `value` node (not its text) for one of `wanted_keys`.
local function find_kv_value(args_node, source, wanted_keys)
  for child in args_node:iter_children() do
    if child:type() == "element_value_pair" then
      local key = child:field("key")[1]
      if key then
        local key_text = vim.treesitter.get_node_text(key, source)
        for _, wanted in ipairs(wanted_keys) do
          if key_text == wanted then
            return child:field("value")[1]
          end
        end
      end
    end
  end
  return nil
end

-- The path string out of a mapping annotation, e.g. "/orders" out of
-- `@GetMapping("/orders")` or `@RequestMapping(value = "/orders")`.
local function extract_path(annotation_node, source)
  local args = annotation_node:field("arguments")[1]
  if not args then
    return nil
  end

  local value_node = find_kv_value(args, source, { "value", "path" })
  if value_node then
    return find_first_string_literal(value_node, source)
  end

  -- Bare single-value form: @GetMapping("/orders") with no `value =`.
  for child in args:iter_children() do
    if child:type() == "string_literal" or child:type() == "array_initializer" then
      return find_first_string_literal(child, source)
    end
  end
  return nil
end

-- The HTTP verb for a mapping annotation. @GetMapping etc. imply their
-- own verb; @RequestMapping needs its `method = RequestMethod.GET` read.
local function extract_verb(annotation_name, annotation_node, source)
  if MAPPING_VERBS[annotation_name] then
    return MAPPING_VERBS[annotation_name]
  end

  if annotation_name == "RequestMapping" then
    local args = annotation_node:field("arguments")[1]
    if args then
      local value_node = find_kv_value(args, source, { "method" })
      if value_node then
        local text = vim.treesitter.get_node_text(value_node, source)
        local verb = text:match("RequestMethod%.(%u+)") or text:match("(%u+)$")
        if verb and REQUEST_METHOD_VERB[verb] then
          return verb
        end
      end
    end
    return "ANY"
  end

  return nil
end

local function join_paths(a, b)
  a, b = a or "", b or ""
  if a == "" then
    return b
  end
  if b == "" then
    return a
  end
  return (a:gsub("/$", "")) .. "/" .. (b:gsub("^/", ""))
end

local function modifiers_child(node)
  for child in node:iter_children() do
    if child:type() == "modifiers" then
      return child
    end
  end
  return nil
end

local function annotations_of(modifiers_node)
  local anns = {}
  if not modifiers_node then
    return anns
  end
  for child in modifiers_node:iter_children() do
    if child:type() == "marker_annotation" or child:type() == "annotation" then
      table.insert(anns, child)
    end
  end
  return anns
end

local function annotation_name(annotation_node, source)
  local name_node = annotation_node:field("name")[1]
  return name_node and vim.treesitter.get_node_text(name_node, source) or nil
end

-- The line to eventually set a breakpoint on: the first statement inside
-- the method body, not the signature line (some debug adapters reject a
-- breakpoint directly on a declaration line). Falls back to the line
-- right after the signature if the body is empty.
local function first_body_line(method_node)
  local signature_row = method_node:range()
  local body = method_node:field("body")[1]
  if not body then
    return signature_row + 1
  end
  local first_statement = body:named_child(0)
  if first_statement then
    return first_statement:range() + 1
  end
  return body:range() + 1
end

local function scan_file(path)
  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return {}
  end
  local source = table.concat(lines, "\n")

  local ok, parser = pcall(vim.treesitter.get_string_parser, source, "java")
  if not ok or not parser then
    return {}
  end
  local root = parser:parse()[1]:root()

  local found = {}

  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "class_declaration" then
        local anns = annotations_of(modifiers_child(child))
        local is_controller, class_prefix = false, ""
        for _, ann in ipairs(anns) do
          local name = annotation_name(ann, source)
          if name == "RestController" or name == "Controller" then
            is_controller = true
          elseif name == "RequestMapping" then
            class_prefix = extract_path(ann, source) or ""
          end
        end

        if is_controller then
          local class_name_node = child:field("name")[1]
          local class_name = class_name_node and vim.treesitter.get_node_text(class_name_node, source) or nil
          local body = child:field("body")[1]

          if body then
            for method in body:iter_children() do
              if method:type() == "method_declaration" then
                for _, ann in ipairs(annotations_of(modifiers_child(method))) do
                  local name = annotation_name(ann, source)
                  local verb = name and extract_verb(name, ann, source)
                  if verb then
                    local method_name_node = method:field("name")[1]
                    -- Full span of the method, so the code view can dim
                    -- everything outside it (1-indexed, inclusive).
                    local start_row, _, end_row, _ = method:range()
                    table.insert(found, {
                      verb = verb,
                      path = join_paths(class_prefix, extract_path(ann, source) or ""),
                      file = path,
                      line = first_body_line(method),
                      method_start_line = start_row + 1,
                      method_end_line = end_row + 1,
                      class_name = class_name,
                      method_name = method_name_node and vim.treesitter.get_node_text(method_name_node, source) or nil,
                    })
                  end
                end
              end
            end
          end
        end
      end
      walk(child)
    end
  end

  walk(root)
  return found
end

-- Scans <root>/src/main/java for every Spring endpoint.
function M.scan(root)
  local files = vim.fn.globpath(root, "src/main/java/**/*.java", false, true)
  local found = {}
  for _, file in ipairs(files) do
    local ok, endpoints_in_file = pcall(scan_file, file)
    if ok then
      vim.list_extend(found, endpoints_in_file)
    end
  end

  table.sort(found, function(a, b)
    if a.path == b.path then
      return a.verb < b.verb
    end
    return a.path < b.path
  end)

  return found
end

return M
