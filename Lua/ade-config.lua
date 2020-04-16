--------------------------------------------------------------------------------------------------
-- script : ade-config.lua
-- author : Dan Gill
-- September 2018
-- version: 1.3
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- desc   : The intention of this script is to set the ade configs throughout the environment.
-- slaves that are not present on master. (The ade probe automatically replicates packages from the
-- This script should run from the primary hub's nas. The folder "script_logs" *MUST* be manually
-- created under the nas directory prior to running this script.
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------

package.path = package.path .. ";./scripts/includes/?.lua" -- Where are your require files?

local output_location = 2 -- 1 = stdout; 2 = file; 3 = both

local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
local fname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) .. ".log"
local fname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) .. "-" .. timestamp.format ( timestamp.now(), "%Y%m%d%H") .. ".log"


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
local robot_master = "/" .. host.domain .. "/" .. host.hubname .. "/" .. host.robotname

if SCRIPT_ARGUMENT ~= nil then
   parms = split(SCRIPT_ARGUMENT)
   if parms ~= nil then
      for k,v in ipairs (parms) do
         if k == 1 then
            robot_master = v
         end
      end
   end
end

local probe_master = robot_master .. "/" .. probe

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Define functions
-----------------------------------------------------------------------
-----------------------------------------------------------------------

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
      output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." FATAL: Error running gethubs callback against primary hub.", output_location)
      codes_file(rc,logfile,output_location)
      return nil, rc
   end
end

-- Check if a probe is running on a host; returns 1 if installed and running and 0 if not.
local function check_probe_running(controller, probe)

   local args = pds.create()
   pds.putString(args, "name", probe)

   local probe_details, rc = nimbus.request(controller, "probe_list" , args)
   pds.delete(args)

   if rc == NIME_OK and probe_details[probe] ~= nil then
      return probe_details[probe].active
   else
      return nil
   end
end

-- Return a table with the full path to specified probe if it is running; excludes "exclude" (send nil exclude to return all)
local function get_probe_paths(exclude, robotlist, probe)
   local probe_paths = {}
   i=1
   for index,_ in pairs(robotlist) do
      local hub = "/" .. robotlist[index].domain .. "/" .. robotlist[index].name .. "/" .. robotlist[index].robotname
      if hub ~= exclude then
         local active = check_probe_running("/" .. robotlist[index].domain .. "/" .. robotlist[index].name .. "/" .. robotlist[index].robotname .. "/controller", probe)
         if active == 1 then
            probe_paths[i] = "/" .. robotlist[index].domain .. "/" .. robotlist[index].name .. "/" .. robotlist[index].robotname .. "/" .. probe
            i = i+1
         end
      end
   end

   return probe_paths
end

local function set_sync_rules(master, logfile)

   local args = pds.create()
   pds.putString(args, "name", "*")
   pds.putString(args, "rule_type", "ALL")

   local resp, rc = nimbus.request(master, "add_package_sync_rule", args)

   pds.delete(args)

   if rc == NIME_OK then
      output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Package Sync Rules added to master. Using * and ALL.", output_location)
      return NIME_OK
   else
      output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." ERROR: Failed to configure package sync rules on master.", output_location)
      codes_file(rc, logfile, output_location)
      return rc
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
               output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Refreshed package sync rules on " .. slave, output_location)
            else
               output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." ERROR: Failed to refresh package sync rules on " .. slave, output_location)
               codes_file(rc, logfile, output_location)
            end
         end
      else
         local tbl,rc = nimbus.request(slave, "refresh_rules")

         if rc == NIME_OK then
            output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Refreshed package sync rules on " .. slave, output_location)
         else
            output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." ERROR: Failed to refresh package sync rules on " .. slave, output_location)
            codes_file(rc, logfile, output_location)
         end
      end
   else
      output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." ERROR: Failed to list package sync rules on " .. slave, output_location)
      codes_file(rc_list, logfile, output_location)
   end

end

local function check_sync_master(master, slave, logfile)

   local ade_info,rc = nimbus.request(slave, "get_info")

   if rc == NIME_OK then
      if ade_info.sync_master == master then
         output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Master is already set correctly on " .. slave, output_location)
         refresh_rules(slave, logfile)
         return NIME_OK
      else
         output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." WARNING: Master is incorrectly set on " .. slave .. " current master = " .. ade_info.sync_master, output_location)
         return 1
      end
   else
      output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." ERROR: Failed to get info from " .. slave, output_location)
      return 0
   end
end

local function set_package_sync_master(master, ade_list, logfile)

   local skip_count = 0
   local change_count = 0

   for _,slave in ipairs (ade_list) do
      local update_master = check_sync_master(master.."/automated_deployment_engine", slave, logfile)
      if update_master == 0 then
         output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Skipping slave " .. slave .. ".\n", output_location)
         skip_count = skip_count + 1
      else
         local args = pds.create()
         pds.putString(args, "robot", master)
         local rc = nimbus.request(slave, "set_package_sync_master", args)
         pds.delete(args)
         output(logfile, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Package sync master set to " .. master .. " on " .. slave .. ".\n", output_location)
         change_count = change_count + 1
      end
   end

   return skip_count, change_count

end

local function main()
   -- Creates/overwrites the file - only do once
   if output_location == 2 or output_location == 3 then
      file.create (fname)
   end

   output(fname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Setting robot_master to " .. robot_master, output_location)

   local hublist = get_hublist(fname)

   local ade_paths = get_probe_paths(robot_master, hublist, probe)

   local rc = set_sync_rules(probe_master, fname)

   local skips, changes = set_package_sync_master(robot_master, ade_paths, fname)

   output(fname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Finished configuring ADE. Skipped " .. skips .. " ADEs and changed " .. changes .. " ADEs.", output_location)

end

main()
