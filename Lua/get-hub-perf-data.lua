--------------------------------------------------------------------------------------------------
-- script : get-hub-perf-data.lua
-- author : Dan Gill
-- June 2020
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- desc   : The intention of this script is to get the max message receive rate for a hub.
-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Set Variables
-----------------------------------------------------------------------
-----------------------------------------------------------------------
package.path = package.path .. ";./scripts/includes/?.lua" -- Where are your require files?
local output_location = 2 -- 1 = stdout; 2 = file; 3 = both

local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
local logfname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) ..
   "-" .. timestamp.format ( timestamp.now(), "%Y%m%d%H") .. ".log"

--local hub_probe_path = "/NMS/T3-MNG-RIU-SNMP-01/riu-snmp01/hub"

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
-----------------------------------------------------------------------
-----------------------------------------------------------------------

require ("error_functions")
require ("logging_functions")
require ("table_functions")

-- Return a list of all hubs under the domain
local function get_hublist()

   local hubs, rc = nimbus.request("hub", "gethubs")
   if rc == NIME_OK then -- If command successful, return hublist
      if hubs.hublist ~= nil then
         return hubs.hublist, rc
      else
         return nil, 110 -- Return code 110 for empty list
      end
   else -- If command fails, log error and code
      output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." FATAL: Error running gethubs callback against primary hub.", output_location)
      codes_file(rc,logfname,output_location)
      return nil, rc
   end
end

-- Calculate max message receive rate per day
local function max_message_receive_rate_on_day(hub_probe, day)
   local args = pds.create()
   pds.putInt(args, "day", day)
   perf_data, rc = nimbus.request(hub_probe, "get_perf_data", args)
   pds.delete(args)

   if rc == NIME_OK and perf_data ~= nil then
      local key, max = 1, perf_data["perf"]["1"].post_received/3600
      for k,_ in pairs(perf_data["perf"]) do
         if perf_data["perf"][k].post_received/3600 > max then
            key, max = k, perf_data["perf"][k].post_received/3600
         end
      end
      return max, NIME_OK
   else
      return nil, rc
   end

end

local function calc_bulk_size(hub)

   local max_message_receive_rate_past_30_days = 0

   for i=1,30,1 do
      local max_messages_received, rc = max_message_receive_rate_on_day(hub, i)
      if rc == NIME_OK then
         if  max_messages_received > max_message_receive_rate_past_30_days then
            max_message_receive_rate_past_30_days = max_messages_received
         end
      end
   end

   -- https://comm.support.ca.com/kb/how-to-optimize-distsrv-probe-performance-when-distributing-superpackages/kb000033940
   local bulk_size = math.ceil (max_message_receive_rate_past_30_days*2.4/100)*100 -- Double and add 20%, then round to nearest 100

   return max_message_receive_rate_past_30_days, bulk_size

end

local function main()
   -- Creates/overwrites the file - only do once
   if output_location == 2 or output_location == 3 then
      file.create (logfname)
   end

   output(logfname,timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Caclulating bulk size on hubs.", output_location)

   -- Get all hubs as seen from nas running this script
   local hublist, rc_hubs = get_hublist()

   if rc_hubs == NIME_OK then -- If command was successful
      for k,_ in pairs (hublist) do -- Cycle through each hub

         local max_message_receive_rate_past_30_days, bulk_size = calc_bulk_size(hublist[k].addr)

         output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Max messages received/sec past 30 days = " .. max_message_receive_rate_past_30_days, output_location)
         output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Bulk size recommendation = " .. bulk_size .. " from " .. hublist[k].addr, output_location)
      end
   end

   output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Script has completed running.", output_location)

end

main()
