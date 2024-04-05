local border = {
   number = { '[', ']' },
   string = { '"', '"' }
}

local function decorate(v)
   local b = border[type(v)]
   if b then
      return b[1] .. tostring(v) .. b[2]
   else
      return tostring(v)
   end
end

---Makes printing table readable
---@param table table
---@param indent number?
function printTable(table, indent, key)
   indent = indent or 1
   if indent > 10 then
      return
   end
   print(string.rep("  ", indent - 1) .. (key and (decorate(key) .. " = ") or "") .. "{")
   for key, value in pairs(table) do
      local vtype = type(value)
      if vtype == "table" then
         printTable(value, indent + 1, key)
      else
         print(string.rep("  ", indent) .. decorate(key) .. " = " .. decorate(value) .. ",")
      end
   end
   print(string.rep("  ", indent - 1) .. "}")
end

local function deepscan(dir)
   local files = love.filesystem.getDirectoryItems(dir)
   local filtered = {}
   for key, file in pairs(files) do
      local meta = love.filesystem.getInfo(dir.."/"..file)
      if meta then
         if meta.type == "directory"  then
            local newfiles = deepscan(dir.."/"..file)
            for key, newfile in pairs(newfiles) do
               filtered[#filtered+1] = newfile
            end
         else
            filtered[#filtered+1] = dir.."/"..file
         end
      end
   end
   return filtered
end

local files = deepscan("src")

local lines = {} ---@type string[]
for key, file in pairs(files) do
   print("Found",file)
   if file:find(".lua$") then
      for line in love.filesystem.lines(file) do
         table.insert(lines, 1, line)
      end
   end
end

everything = {}


-->====================[ CLASS SCRAPING ]====================<--
for i = 1, #lines, 1 do
   local mline = lines[i]
   if mline:find("^%-%-%-@class") then
      local class_data = mline:match("^%-%-%-@class[%s]*([%s%S]*)") .. ":"
      local class_name, class_inheritance = class_data:match("([%w_.]+)[%s]*:[%s]*([%w_.]*)")

      local class_data = {
         methods = {},
         fields = {},
         description = {}
      }
      if #class_inheritance ~= 0 then class_data.inheritance = class_inheritance end
      local class_var = class_name
      class_data.class_name = class_name
      for o = 1, 1000, 1 do
         local line = lines[i - o]
         if line:find("^%-%-%-@field") then -- FIELD
            local special
            if line:find("^%-%-%-@field protected") then
               line = line:gsub("@field protected","@field")
               special = "protected"
            elseif line:find("^%-%-%-@field private") then
               line = line:gsub("@field private","@field")
               special = "private"
            elseif line:find("^%-%-%-@field public") then
               line = line:gsub("@field public","@field")
               special = "public"
            elseif line:find("^%-%-%-@field package") then
               line = line:gsub("@field package","@field")
               special = "package"
            end
            local name, type, comment = (line.."#"):match("^%-%-%-@field[%s]+([%w_]+)[%s]+([^#]+)([%S%s]*)")
            comment = comment:sub(2,-2)
            type = type:gsub("^%s*(.-)%s*$", "%1")
            class_data.fields[#class_data.fields+1] = {type=type,name=name,description = #comment ~= 0 and comment or "...",special = special}
         elseif line:find("local[%s]+[%w_]+[%s]*=") then -- class variable name
            class_var = line:match("local[%s]+([%w_]+)[%s]*=")
         else
            break
         end
      end
      class_data.class_name = class_name
      class_data.class_var_name = class_var
      table.sort(class_data.fields, function (a, b)return string.upper(a.name) < string.upper(b.name)end)
      everything[class_var] = class_data
   end
end

-->====================[ METHOD/FUNCTION SCRAPING ]====================<--
for i = 1, #lines, 1 do
   local line = lines[i]
   if line:match("^function") then
      local func = line:match("function ([%S]+)%(")
      local method = {
         func = func,
         description = {},
         overloads = {
            {
               parameters = {},
               returns = {},
            },
         },
      }
      for c = 1, 1000, 1 do
         local line = lines[i + c]
         if line:find("^%-%-%-@param") then -- PARAMETER
            local parameter = {}
            local name, meta = line:match("^%-%-%-@param[%W]+([%w_.]+)[%W]+([%w%W]*)$")
            local type, post = meta:match("^([%S]+)([%w%W]*)")
            parameter.name = name
            parameter.type = type
            local desc = post:match("[%s]*#[%s]*([%W%w]*)$")
            if desc then
               parameter.desc = desc
            end
            table.insert(method.overloads[1].parameters, 1, parameter)
         elseif line:find("^%-%-%-@overload") then -- OVERLOAD
            local parameters = {}
            local parameters_string, return_string
            if line:match(":[%s]([%S])[%s]*$") then
               parameters_string, return_string = line:match("^%-%-%-@overload fun(%([%s%S]*%)):%f[ ]([%s%S]*)")
            else
               parameters_string = line:match("^%-%-%-@overload fun(%([%s%S]*%))")
               return_string = "nil"
            end
            local i = #method.overloads + 1

            -- split returns in an overload
            local returns = {}
            for word in string.gmatch((return_string) .. ",", "[%s%S]*,") do
               returns[#returns + 1] = word:sub(1, -2)
            end

            for param in string.gmatch(string.sub(parameters_string, 2, -2) .. ",", "[%s]*([%w_.: ]+),") do
               local name, type = (param .. ":"):match("([%w_]+)[%s]*:[%s]*([%w_.]*)")
               if name ~= "self" then
                  parameters[#parameters + 1] = { type = (#type ~= 0 and type or "any"), name = name }
               end
            end

            method.overloads[i] = {
               parameters = parameters,
               returns = returns,
            }
         elseif line:find("^%-%-%-@return") then -- RETURN
            local type = line:match("^%-%-%-@return[%s]*([%S]+)")
            table.insert(method.overloads[1].returns, 1, type)
         elseif line:find("^%-%-%-") then -- DESCRIPTION
            table.insert(method.description, 1, line:sub(4, -1))
         elseif line:find("^%-%-%-@") then -- OTHER
         else
            break
         end
      end
      local class = method.func:match("^([%w_*]+)")
      if not everything[class] then -- no class declared for given table
         everything[class] = {
            methods = {},
            fields = {},
            description = {}
         }
      end
      table.insert(everything[class].methods, 1, method)
   end
end

-- Print contents of `tbl`, with indentation.
-- `indent` sets the initial level of indentation.
function tprint(tbl, indent)
   if not indent then indent = 0 end
   for k, v in pairs(tbl) do
      formatting = string.rep("  ", indent) .. k .. ": "
      if type(v) == "table" then
         print(formatting)
         tprint(v, indent + 1)
      elseif type(v) == 'boolean' then
         print(formatting .. tostring(v))
      else
         print(formatting .. v)
      end
   end
end

-->========================================[ BAKE ]=========================================<--

print(" Processing...")

local bake = ""
for class_name, class_data in pairs(everything) do
   bake = ""
   if class_data.class_name then
      bake = bake .. "### Class Name: `"..class_data.class_name .. "`\n"
   end
   if class_data.inheritance then
      bake = bake .. "Inherits from: `"..class_data.inheritance.."`\n"
   end
   for key, line in pairs(class_data.description) do
      bake = bake .. line .. "\n"
   end

   if #class_data.fields > 0 then
      local has_events = false
      bake = bake .. "# Properties\n"
      bake = bake .. "|Type|Field|Description| |\n"
      bake = bake .. "|-|-|-|-|\n"
      for _, field in pairs(class_data.fields) do
         if field.type:find("EventLib") then
            has_events = true
         else
            bake = bake .. "|`"..(field.type:gsub("|", "｜")).."`|"..field.name.."|"..field.description:gsub("|", "｜").."|"..(field.special or " ").."|\n"
         end
      end
      if has_events then
         bake = bake .. "# Events\n"
         bake = bake .. "|Event|Description|\n"
         bake = bake .. "|-|-|\n"
         for _, field in pairs(class_data.fields) do
            if field.type:find("EventLib") then
               bake = bake .. "|`"..field.name.."`|"..(field.description and field.description:gsub("|", "｜") or "...").."|\n"
            end
         end
      end
   end

   bake = bake .. "# Methods\n"
   
   
   bake = bake .. "|Returns|Methods|\n"
   bake = bake .. "|-|-|\n"
   for _, method in pairs(class_data.methods) do
      for _, func in pairs(method.overloads) do
         bake = bake .. "|"
         for key, query in pairs(func.returns) do
            bake = bake .. "`" .. query .. "`"
         end
   
         local params = ""
         for key, value in pairs(func.parameters) do
            params = params .. value.name .. " : " .. value.type:gsub("|", "｜") .. (key ~= #func.parameters and ", " or "")
         end
   
         local params_no_type = ""
         for key, value in pairs(func.parameters) do
            params_no_type = params_no_type .. value.name .. (key ~= #func.parameters and ", " or "")
         end
   
         local class, call, method_name = method.func:match("^([%w_*]+)(.)([%w_*]+)")
   
         local path = string.gsub(method.func .. "(" .. params_no_type .. ")", "[^%w _]", ""):gsub(" ", "-")
         bake = bake .. "|" .. (class) .. call .. "[" .. method_name .. "](#" .. path .. ")" .. "(" .. params .. ")"
         bake = bake .. "|\n"
      end
   end
   
   for _, method in pairs(class_data.methods) do
      for _, overloads in pairs(method.overloads) do
         -- Method title
         bake = bake .. "## `" .. method.func
         bake = bake .. "("
         for i, param in pairs(overloads.parameters) do
            bake = bake .. param.name
            if i ~= #overloads.parameters then
               bake = bake .. ", "
            end
         end
         bake = bake .. ")"
         bake = bake .. "`\n"
   
         -- Method Description
         if #method.description ~= 0 then
            for i, line in pairs(method.description) do
               bake = bake .. line .. "  \n"
            end
         end
   
         -- Method arguments
         if #overloads.parameters ~= 0 then
            bake = bake .. "### Arguments\n"
            for i, param in pairs(overloads.parameters) do
               bake = bake .. "- `" .. param.type .. "` `" .. param.name .. "`\n"
               if param.desc then
                  bake = bake .. "  - " .. param.desc .. "\n"
               else
                  bake = bake .. "\n"
               end
            end
         end
   
         -- Method returns
         if #overloads.returns ~= 0 then
            bake = bake .. "### Returns\n"
            for _, query in pairs(overloads.returns) do
               bake = bake .. "  - `" .. query .. "`\n"
            end
         end
         bake = bake .. "\n"
      end
   end
   local filename = class_name:upper():sub(1,1) .. class_name:lower():sub(2,-1) .. ".md"
   local ok, err = love.filesystem.write(filename, bake)
   if ok then
      print("Saved",filename)
   else
      print("Error saving",filename,err)
   end
end

bake = "# Documentation\n"

local toc = {}
for key, value in pairs(everything) do
   toc[#toc+1] = key
end

table.sort(toc, function (a, b)return string.upper(a) < string.upper(b)end)

for _, class_name in pairs(toc) do
   bake = bake .. "- ### [" .. class_name:upper():sub(1,1) .. class_name:lower():sub(2,-1) .. "]("..class_name..")" .. "\n"
end

local ok, err = love.filesystem.write("_Sidebar.md", bake)
if ok then
   print("Saved","_Sidebar.md")
else
   print("Error saving","_Sidebar.md",err)
end