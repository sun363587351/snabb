module(..., package.seeall)

local S          = require("syscall")
local config     = require("core.config")
local lib        = require("core.lib")
local setup      = require("program.snabbvmx.lwaftr.setup")

local function show_usage(exit_code)
   print(require("program.snabbvmx.lwaftr.README_inc"))
   if exit_code then main.exit(exit_code) end
end

local function fatal(msg)
   print(msg)
   main.exit(1)
end

local function file_exists(path)
   local stat = S.stat(path)
   return stat and stat.isreg
end

local function dir_exists(path)
  local stat = S.stat(path)
  return stat and stat.isdir
end

local function nic_exists(pci_addr)
  local devices="/sys/bus/pci/devices"
  return dir_exists(("%s/%s"):format(devices, pci_addr)) or
  dir_exists(("%s/0000:%s"):format(devices, pci_addr))
end

function parse_args(args)
   if #args == 0 then show_usage(1) end
   local conf_file, sock_path, v6_id, v6_pci, v6_mac, v4_id, v4_pci, v4_mac
   local opts = { verbosity = 0 }
   local handlers = {}
   function handlers.v () opts.verbosity = opts.verbosity + 1 end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration must be a number")
   end
   function handlers.c(arg)
     conf_file = arg
     if not arg then
       fatal("Argument '--conf' was not set")
     end
     if not file_exists(conf_file) then
       print(string.format("warning: config file %s not found", conf_file))
     end
   end
   function handlers.i(arg)
      id = arg
      if not arg then
         fatal("Argument '--id' was not set")
      end
   end
   function handlers.p(arg)
      pci = arg
      if not arg then
         fatal("Argument '--pci' was not set")
      end
   end
   function handlers.m(arg)
      mac = arg
      if not arg then
         fatal("Argument '--mac' was not set")
      end
   end
   function handlers.s(arg)
      sock_path = arg
      if not arg then
         fatal("Argument '--sock' was not set")
      end
   end
   function handlers.h() show_usage(0) end
   lib.dogetopt(args, handlers, "c:s:i:p:m:vD:ht",
      { ["conf"] = "c", ["sock"] = "s", 
        ["id"] = "i", ["pci"] = "p", ["mac"] = "m",
        verbose = "v", duration = "D", help = "h" })
   return opts, conf_file, id, pci, mac, sock_path
end

function run(args)
   local opts, conf_file, id, pci, mac, sock_path = parse_args(args)

   local conf = {}
   local lwconf = {}
   if file_exists(conf_file) then
     conf = lib.load_conf(conf_file)
     if not file_exists(conf.lwaftr) then
       fatal(("lwaftr conf file %s not found"):format(conf.lwaftr))
     end
     lwconf = require('apps.lwaftr.conf').load_lwaftr_config(conf.lwaftr)
     lwconf.ipv6_mtu = lwconf.ipv6_mtu or 1500
     lwconf.ipv4_mtu = lwconf.ipv4_mtu or 1460
   else
     print(string.format("interface %s set to passhtru mode", id))
   end

   local c = config.new()

   if conf.settings then
     if conf.settings.ring_buffer_size then
       local ring_buffer_size = tonumber(conf.settings.ring_buffer_size)
       if not ring_buffer_size then fatal("bad ring size: " .. conf.settings.ring_buffer_size) end
       if ring_buffer_size > 32*1024 then
         fatal("ring size too large for hardware: " .. ring_buffer_size)
       end
       if math.log(ring_buffer_size)/math.log(2) % 1 ~= 0 then
         fatal("ring size is not a power of two: " .. ring_buffer_size)
       end
       print(string.format("ring_buffer_size set to %d", ring_buffer_size))
       require('apps.intel.intel10g').num_descriptors = ring_buffer_size
     end
   end

   conf.interface = { mac_address = mac, pci = pci, id = id }
   if dir_exists(("/sys/devices/virtual/net/%s"):format(id)) then
     conf.interface.mirror_id = id
   end

   setup.lwaftr_app(c, conf, lwconf, sock_path )

   engine.configure(c)

   if opts.verbosity >= 2 then
     local function lnicui_info()
       engine.report_apps()
     end
     local t = timer.new("report", lnicui_info, 1e9, 'repeating')
     timer.activate(t)
   end

   engine.busywait = true
   if opts.duration then
      engine.main({duration=opts.duration, report={showlinks=true}})
   else
      engine.main({report={showlinks=true}})
   end
end
