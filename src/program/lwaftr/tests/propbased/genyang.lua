module(..., package.seeall)

--local S = require("syscall")
--local snabb_cmd = ("/proc/%d/exe"):format(S.getpid())

local schema = require("lib.yang.schema")
local softwire_schema = schema.load_schema_by_name("snabb-softwire-v1")

function generate_get(pid, query)
   if not query then
      query = generate_config_xpath()
   end
   return string.format("./snabb config get %s \"%s\"", pid, query)
end

function generate_get_state(pid, query)
   if not query then
      query = generate_config_xpath_state()
   end
   return string.format("./snabb config get-state %s \"%s\"", pid, query)
end

function generate_set(pid, query, val)
   return string.format("./snabb config set %s \"%s\" \"%s\"", pid, query, val)
end

function run_yang(yang_cmd)
   local f = io.popen(yang_cmd)
   local result = f:read("*a")
   f:close()
   return result
end

-- choose an element of an array randomly
local function choose(choices)
   local idx = math.random(#choices)
   return choices[idx]
end

-- choose from unbounded array indices, decreasing likelihood
local function choose_pos()
   local r = math.random()

   local function flip(next)
      local r = math.random()
      if r < 0.5 then
         return next
      else
         return flip(next + 1)
      end
   end

   -- evenly weight first five indices
   if r < 0.5 then
      return choose({1, 2, 3, 4, 5})
   else
      return flip(6)
   end
end

local function value_from_type(a_type)
   local prim = a_type.primitive_type

   if prim == "int8" then
      return math.random(-128, 127)
   elseif prim == "int16" then
      return math.random(-32768, 32767)
   elseif prim == "int32" then
      return math.random(-2147483648, 2147483647)
   elseif prim == "int64" then
      return math.random(-9223372036854775808, 9223372036854775807)
   elseif prim == "uint8" then
      return math.random(0, 255)
   elseif prim == "uint16" then
      return math.random(0, 65535)
   elseif prim == "uint32" then
      return math.random(0, 4294967295)
   elseif prim == "uint64" then
      return math.random(0, 18446744073709551615)
   --elseif prim == "decimal64" then
   --   local int64 = value_from_type("int64")
   --   local exp   = math.random(1, 18)
   --   return int64 * (10 ^ -exp)
   elseif prim == "boolean" then
      return choose({ true, false })
   elseif prim == "ipv4-address" then
      return math.random(0, 255) .. "." .. math.random(0, 255) .. "." ..
             math.random(0, 255) .. "." .. math.random(0, 255)
   end

   -- TODO: generate these:
   -- string
   -- binary
   -- bits
   -- empty
   -- enumeration
   -- identityref
   -- instance-identifier
   -- leafref
   -- union

   -- unknown type
   return nil
end

-- from a config schema, generate an xpath query string
-- this code is patterned off of the visitor used in lib.yang.data
local function generate_xpath(schema, for_state)
   local path = ""
   local handlers = {}

   local function visit(node)
      local handler = handlers[node.kind]
      if handler then handler(node) end
   end
   local function visit_body(node)
      local ids = {}
      for id, node in pairs(node.body) do
         -- only choose nodes that are used in configs unless
         -- for_state is passed
         if for_state or node.config ~= false then
            table.insert(ids, id)
         end
      end

      local id = choose(ids)
      if id then
         visit(node.body[id])
      end
   end
   function handlers.container(node)
      path = path .. "/" .. node.id

      -- don't always go into containers, since we need to test
      -- fetching all sub-items too
      if math.random() < 0.9 then
         visit_body(node)
      end
   end
   handlers['leaf-list'] = function(node)
      local selector = string.format("[position()=%d]", choose_pos())
      path = path .. "/" .. node.id .. selector
   end
   function handlers.list(node)
      local key_types = {}
      local r = math.random()

      path = path .. "/" .. node.id

      -- occasionally drop the selectors
      if r < 0.9 then
         for key in (node.key):split(" +") do
            key_types[key] =  node.body[key].type
         end

         for key, type in pairs(key_types) do
            local val = assert(value_from_type(type), type)
            path = path .. string.format("[%s=%s]", key, val)
         end
      end
   end
   function handlers.leaf(node)
      path = path .. "/" .. node.id
   end

   -- just produce "/" on rare occasions
   if math.random() > 0.01 then
      visit_body(schema)
   end

   return path
end

function generate_config_xpath()
   return generate_xpath(softwire_schema, false)
end

function generate_config_xpath_state()
   local path = generate_xpath(softwire_schema.body["softwire-state"], true)
   return "/softwire-state" .. path
end

function selftest()
   local data = require("lib.yang.data")
   local path = require("lib.yang.path")
   local grammar = data.data_grammar_from_schema(softwire_schema)

   path.convert_path(grammar, generate_xpath(softwire_schema))
end
