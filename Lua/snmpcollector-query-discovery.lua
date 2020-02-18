--------------------------------------------------------------------------------
-- script : snmpcollector-query-discovery.lua
-- author : Dan Gill
-- January 2020
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- desc   : The intention of this script is to automate the process of querying
-- the discovery_server from the snmpcollector probe.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Set Variables
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Where are your require files?
package.path = package.path .. ";./scripts/includes/?.lua"

local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
local logfile = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) ..
   "-" .. timestamp.format ( timestamp.now(), "%Y%m%d%H") .. ".log"
local output_location = 3 -- 1 = stdout; 2 = file; 3 = both

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

require ("logging_functions")
require ("error_functions")
require ("table_functions")

local function get_hublist()
   -- Return a list of all hubs under the domain
   local hubs, rc = nimbus.request("hub", "gethubs")
   if rc == NIME_OK then -- If command successful, return hublist
      if hubs.hublist ~= nil then
         return hubs.hublist, rc
      else
         return " ERROR: Empty hub list.", 110 -- Return code 110 for empty list
      end
   else -- If command fails, log error and code
      return " FATAL: Error running gethubs callback against primary hub.", rc
   end
end

local function check_probe_running(controller, probe)
   -- Check if a probe is running on a host. If installed, returns 1 if running
   -- and 0 if not. Returns error message and rc otherwise.
   local args = pds.create()
   pds.putString(args, "name", probe)

   local probe_details, rc = nimbus.request(controller, "probe_list", args)
   pds.delete(args)

   if rc == NIME_OK and probe_details[probe] ~= nil then
      return probe_details[probe].active, rc
   elseif rc ~= NIME_OK then
      return " FATAL: Failed to get probe list from "..controller, rc
   else
      return " INFO: Probe not installed", 4
   end
end

local function load_from_discovery_serv(probe_path)
   res_tbl, rc = nimbus.request(probe_path, "load_from_discovery_serv")

   if rc == NIME_OK then
      if res_tbl.Status == "SUCCESS" then
         return res_tbl["Result:"], rc
      else
         -- Return error
         return " ERROR: " .. res_tbl["Result:"], 1
      end
   else
      return " FATAL: Return Code NOT OK when loading from discovery_server "..
         "on "..probe_path,rc
   end
end

local function main()
   if output_location == 2 or output_location == 3 then
      -- Creates/overwrites the file - only do once
      file.create (logfile)
   end

   output(logfile,timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S")..
      " INFO: Querying discovery_server from snmpcollector hubs.",
      output_location)

   local hublist, rc_hubs = get_hublist()

   if rc_hubs == NIME_OK then
      for k,_ in pairs(hublist) do
         if hublist[k].status ~= NIME_COMERR then
            local controller = "/" .. hublist[k].domain .. "/" ..
               hublist[k].name .. "/" .. hublist[k].robotname .. "/controller"
            local snmpcollector_status, rc_status =
               check_probe_running(controller, "snmpcollector")
            if rc_status == NIME_OK and snmpcollector_status == 1 then
               local snmpcollector = "/" .. hublist[k].domain .. "/" ..
                  hublist[k].name.."/"..hublist[k].robotname .."/snmpcollector"
               output(logfile,timestamp.format (timestamp.now(),
                  "%Y-%m-%d %H:%M:%S").." INFO: Probe active: "..snmpcollector,
                  output_location)
               local result, rc_load = load_from_discovery_serv(snmpcollector)
               if rc_load ~= NIME_OK then
                  output(logfile,timestamp.format (timestamp.now(),
                     "%Y-%m-%d %H:%M:%S")..result, output_location)
                  codes_file(rc_load, logfile, output_location)
               else
                  output(logfile,timestamp.format (timestamp.now(),
                     "%Y-%m-%d %H:%M:%S")..
                     " INFO: Queried discovery_server on "..snmpcollector,
                     output_location)
               end
            elseif rc_status ~= NIME_OK and rc_status ~= 4 then
               output(logfile,timestamp.format (timestamp.now(),
                  "%Y-%m-%d %H:%M:%S")..snmpcollector_status, output_location)
               codes_file(rc_status, logfile, output_location)
            end
         else
            output(logfile,timestamp.format (timestamp.now(),
               "%Y-%m-%d %H:%M:%S").." ERROR: Hub status invalid: " ..
               hublist[k].name, output_location)
            codes_file(hublist[k].status, logfile, output_location)
         end
      end
   else
      output(logfile,timestamp.format (timestamp.now(),"%Y-%m-%d %H:%M:%S") ..
         hublist, output_location)
      codes_file(rc_hubs, logfile, output_location)
   end

   output(logfile,timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S")..
      " INFO: Script has completed running.",
      output_location)
end

main()
