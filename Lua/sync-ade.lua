--------------------------------------------------------------------------------
-- script : sync-ade.lua
-- author : Dan Gill
-- September 2018
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- desc   : The intention of this script is to synchronize ade probes by
-- deleting packages from slaves that are not present on master. (The ade probe
-- automatically replicates packages from the master to the slaves but does not
-- delete automatically.)
-- This script should be run by the nas with an argument passed to it. The
-- argument must be the master ade name in the format /DOMAIN/HUB/ROBOT
-- Alternatively, the script may be run manually and will use the ade probe
-- located on the hub the script is run from. The folder "script_logs" *MUST* be
-- manually created under the nas directory prior to running this script.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Set Variables
-----------------------------------------------------------------------
-----------------------------------------------------------------------

-- Where are your require files?
package.path = package.path .. ";./scripts/includes/?.lua"
local output_location = 2 -- 1 = stdout; 2 = file; 3 = both

local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
local fname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) .. "-" ..
   timestamp.format ( timestamp.now(), "%Y%m%d") .. ".log"

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
-----------------------------------------------------------------------
-----------------------------------------------------------------------

require ("error_functions")
require ("logging_functions")
require ("table_functions")

local probe = "automated_deployment_engine"
local host = nimbus.request("controller", "get_info")
local robot_master = "/" .. host.domain .. "/" .. host.hubname .. "/" ..
   host.robotname
local exclude = robot_master .. "/" .. probe

if SCRIPT_ARGUMENT ~= nil then
   parms = split(SCRIPT_ARGUMENT)
   for k,v in ipairs (parms) do
      if k == 1 then
         robot_master = v
      end
   end
end

local probe_master = robot_master .. "/" .. probe

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Define functions
-----------------------------------------------------------------------
-----------------------------------------------------------------------

--------------------------------------------------------------------------------
-- get_packages()
--
-- Return list of packages from automated_deployment_engine probe with CRC for
-- each version
--------------------------------------------------------------------------------
function get_packages (automated_deployment_engine)

   -- Get list of packages from automated_deployment_engine
   local resp,rc = nimbus.request(automated_deployment_engine, "archive_list")

   if resp ~= nil then
      if resp.entry ~= nil then
         -- Extract version and crc for each package into table
         local pkg_list = {}
         for _,v in pairs(resp.entry) do
            local pkg_version = "NOVERSION"
            local pkg_crc   = "NOCRC"

            if v.version ~= "" and v.version ~= nil then
               pkg_version = v.version
            end

            if v.crc ~= "" and v.crc ~= nil then
               pkg_crc = v.crc
            end

            if pkg_list[v.name] == nil then
               pkg_list[v.name] = {}
            end

            pkg_list[v.name][pkg_version] = pkg_crc
         end

         -- Return list
         return pkg_list
      else
         output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S")
            .. " Failed to get archive list from " ..
            automated_deployment_engine, output_location)
         return nil
      end
   else
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " Failed to get archive list from " .. automated_deployment_engine,
         output_location)
      return nil
   end
end

--------------------------------------------------------------------------------
-- delete_package()
--
-- Delete package from automated_deployment_engine probe
--------------------------------------------------------------------------------
function delete_package (automated_deployment_engine,package,version)

   -- Build PDS to specify which package to remove
   local args = pds.create()
   pds.putString(args, "name", package)
   pds.putString(args, "version", version)

   -- Send request
   local rc = nimbus.request(automated_deployment_engine, "archive_delete"
      , args)
   pds.delete(args)

   -- Print result
   if rc == NIME_OK then
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " INFO: Deleted " .. package .. " " .. version .. " from " ..
         automated_deployment_engine, output_location)
   elseif rc ~= nil then
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
      " WARNING: Failed to delete " .. package .. " " .. version .. " from " ..
      automated_deployment_engine, output_location)
      if type(rc) == "table" then
         tdump_file(rc,fname,output_location)
      else
         codes_file(rc,fname,output_location)
      end
   else
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
      " WARNING: Empty return code received while deleting " .. package .. " "
      .. version .. " from " .. automated_deployment_engine, output_location)
   end
end

function delete_package_distsrv (distsrv,package,version)

   -- If the version is NOVERSION, we need to set it to nil
   if version == "NOVERSION" then
      version = nil
   end

   -- Build PDS to specify which package to remove
   local args = pds.create()
   pds.putString(args, "name", package)
   if version ~= nil then
      pds.putString(args, "version", version)
   end

   -- Send request
   local rc = nimbus.request(distsrv, "archive_delete" , args)
   pds.delete(args)

   -- Print result
   if version == nil then
      version = "NOVERSION"
   end
   if rc == NIME_OK then
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " INFO: Deleted " .. package .. " " .. version .. " from " .. distsrv,
         output_location)
   elseif rc ~= nil then
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " WARNING: Failed to delete " .. package .. " " .. version .. " from "
         .. distsrv, output_location)
      codes_file(rc,fname,output_location)
   else
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " WARNING: Empty return code received while deleting " .. package ..
         " " .. version .. " from " .. distsrv, output_location)
   end
end

-- Return a list of all hubs under the domain
local function get_hublist(logfile)

   local hubs, rc = nimbus.request("hub", "gethubs")
   if rc == NIME_OK then -- If command successful, return hublist
      if hubs.hublist ~= nil then
         return hubs.hublist, rc
      else
         return nil, 110 -- Return code 110 for empty list
      end
   else -- If command fails, log error and code
      output(logfile, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " FATAL: Error running gethubs callback against primary hub.",
         output_location)
      codes_file(rc,logfile,output_location)
      return nil, rc
   end
end

local function tablelength(T)
   local count = 0
   for _ in pairs(T) do count = count + 1 end
   return count
end

local function refresh_rules(slave, logfile)

   local rules_list,rc_list = nimbus.request(slave, "list_rules")

   if rc_list == NIME_OK then
      if rules_list ~= nil then
         if tablelength(rules_list) == 0 then
            local tbl,rc = nimbus.request(slave, "refresh_rules")

            if rc == NIME_OK then
               output(logfile, timestamp.format(timestamp.now(),
                  "%Y-%m-%d %H:%M:%S") ..
                  " INFO: Refreshed package sync rules on " .. slave,
                  output_location)
            else
               output(logfile, timestamp.format(timestamp.now(),
                  "%Y-%m-%d %H:%M:%S") ..
                  " ERROR: Failed to refresh package sync rules on " .. slave,
                  output_location)
               codes_file(rc, logfile, output_location)
            end
         end
      else
         local tbl,rc = nimbus.request(slave, "refresh_rules")

         if rc == NIME_OK then
            output(logfile, timestamp.format(timestamp.now(),
               "%Y-%m-%d %H:%M:%S") .. " INFO: Refreshed package sync rules on "
               .. slave, output_location)
         else
            output(logfile, timestamp.format(timestamp.now(),
               "%Y-%m-%d %H:%M:%S") ..
               " ERROR: Failed to refresh package sync rules on " .. slave,
               output_location)
            codes_file(rc, logfile, output_location)
         end
      end
   else
      output(logfile, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " ERROR: Failed to list package sync rules on " .. slave,
         output_location)
      codes_file(rc_list, logfile, output_location)
   end

end

-- Check if a probe is running on a host; returns 1 if installed and running,
-- and 0 if not.
local function check_probe_running(controller, probe)

   local args = pds.create()
   pds.putString(args, "name", probe)

   local probe_details, rc = nimbus.request(controller, "probe_list" , args)
   pds.delete(args)

   if rc == NIME_OK and probe_details[probe] ~= nil then
      return probe_details[probe].active
   else
      return 0
   end
end

-- Return a table with the full path to specified probe if it is running;
-- excludes "exclude" (send nil exclude to return all)
local function get_probe_paths(exclude, robotlist, probe)
   local probe_paths = {}
   i=1
   for index,_ in pairs(robotlist) do
      local hub = "/" .. robotlist[index].domain .. "/" .. robotlist[index].name
         .. "/" .. robotlist[index].robotname
      if hub ~= exclude then
         local active = check_probe_running("/" .. robotlist[index].domain ..
            "/" .. robotlist[index].name .. "/" .. robotlist[index].robotname ..
            "/controller", probe)
         if active == 1 then
            probe_paths[i] = "/" .. robotlist[index].domain .. "/" ..
               robotlist[index].name .. "/" .. robotlist[index].robotname .. "/"
               .. probe
            i = i+1
         end
      end
   end

   return probe_paths
end

local function restart_probe(controller, probe)

   local slave = string.sub(controller, 1, string.len(controller) -
      string.len("controller"))
   local args = pds.create()
   pds.putString(args, "name", probe)

   local stop_result, rc_stop = nimbus.request(controller, "probe_deactivate",
      args)

   if rc_stop ~= NIME_OK then
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " ERROR: Failed to stop slave " .. probe ..  " on " .. slave .. ".",
         output_location)
      codes_file(rc_stop,fname,output_location)
   end

   sleep(60000) -- Wait 60 seconds for probe to stop before restarting

   local start_result, rc_start = nimbus.request(controller, "probe_activate",
      args)
   pds.delete(args)

   if rc_start ~= NIME_OK then
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " ERROR: Failed to start slave " .. probe ..  " on " .. slave .. ".",
         output_location)
      codes_file(rc_start,fname,output_location)
   end

end


--------------------------------------------------------------------------------
-- MAIN ENTRY
--------------------------------------------------------------------------------

local function main()
   if output_location == 2 or output_location == 3 then
      file.create (fname)
   end

   output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
      " Setting robot_master to " .. robot_master, output_location)


   local i = 1
   -- Get package lists from both automated_deployment_engine probes
   local pkgs_master = get_packages(probe_master)

   -- Make sure we got results from master
   if pkgs_master == nil then
       return
   else
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " INFO: Got package list from master automated_deployment_engine (" ..
         probe_master .. ").", output_location)
   end

   local automated_deployment_engine_slaves = get_probe_paths(robot_master,
      get_hublist(), probe)

   for _, slave in ipairs (automated_deployment_engine_slaves) do

      refresh_rules(slave, fname) -- Refresh rules on ADE if it is empty.
      output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
         " INFO: Getting package list for slave " .. slave, output_location)

      local pkgs_slave = get_packages( slave )

      if pkgs_slave ~= nil then
         output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
            " INFO: Got package list from slave automated_deployment_engine ("
            .. slave .. ").", output_location)
         -- Check all packages on slave automated_deployment_engine
         for name,details in pairs(pkgs_slave) do

            -- Check all versions of this package on slave
            for version,crc in pairs (details) do
               -- Check if this version of package exists on primary
               if pkgs_master[name] == nil or
                  pkgs_master[name][version] == nil then
                  -- This version of package not on primary;
                  -- delete from secondary
                  if version == "NOVERSION" then
                     local distsrv_slave = string.sub(slave, 1,
                        string.len(slave) - string.len(probe)).."distsrv"
                     delete_package_distsrv( distsrv_slave, name, version)
                  else
                     delete_package( slave, name, version )
                  end
               elseif pkgs_master[name][version] ~= crc then
                  -- If the CRC isn't the same then the package is corrupt.
                  -- Delete so resync can occur.
                  output(fname, timestamp.format(timestamp.now(),
                     "%Y-%m-%d %H:%M:%S") .. " WARN: CRC mismatch on " .. name
                     .. ". Deleting to allow resync.", output_location)
                  if version == "NOVERSION" then
                     local distsrv_slave = string.sub(slave, 1,
                        string.len(slave) - string.len(probe)).."distsrv"
                     delete_package_distsrv( distsrv_slave, name, version)
                  else
                     delete_package( slave, name, version )
                  end
               end
            end
         end
         i = i+1
      else
         output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
            " ERROR: Failed to get package list from slave automated_deployment_engine ("
            .. slave .. ").", output_location)
      end

      local controller = string.sub(slave, 1, string.len(slave) -
         string.len(probe)).."controller"
      restart_probe(controller, probe) -- Restart ADE
      restart_probe(controller, "distsrv") -- Restart distsrv

   end

   output(fname, timestamp.format(timestamp.now(), "%Y-%m-%d %H:%M:%S") ..
      " INFO: Finished. " .. i .. " slaves processed.", output_location)
end

main()
