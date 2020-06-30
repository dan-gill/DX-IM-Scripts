--------------------------------------------------------------------------------------------------
-- script : get-hub-perf-data.lua
-- author : Dan Gill
-- February 2019
-- version: 1.0
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- desc   : The intention of this script is to get the max message receive rate for a hub.

---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- Version  | Details
---------------------------------------------------------------------------------------------------
-- 1.0      | Initial Version
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Set Variables
-----------------------------------------------------------------------
-----------------------------------------------------------------------
package.path = package.path .. ";./scripts/includes/?.lua" -- Where are your require files?
local output_location = 1 -- 1 = stdout; 2 = file; 3 = both

local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
local fname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) .. ".log"

local hub_probe_path = "/NMS/T3-MNG-RIU-SNMP-01/riu-snmp01/hub"

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
-----------------------------------------------------------------------
-----------------------------------------------------------------------

require ("error_functions")
require ("logging_functions")
require ("table_functions")

local function max_message_receive_rate_on_day(hub_probe, day)
   local args = pds.create()
   pds.putInt(args, "day", day)
   perf_data, rc = nimbus.request(hub_probe, "get_perf_data", args)
   pds.delete(args)

   if rc == NIME_OK then
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

local function main()
   local max_message_receive_rate_past_30_days = 0

   for i=1,30,1 do
      local max_messages_received, rc = max_message_receive_rate_on_day(hub_probe_path, i)
      if rc == NIME_OK then
         if  max_messages_received > max_message_receive_rate_past_30_days then
            max_message_receive_rate_past_30_days = max_messages_received
         end
      end
   end

   -- https://comm.support.ca.com/kb/how-to-optimize-distsrv-probe-performance-when-distributing-superpackages/kb000033940
   local bulk_size = math.ceil (max_message_receive_rate_past_30_days*2.4/100)*100 -- Double and add 20%, then round to nearest 100

   output(fname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Max messages received/sec past 30 days = " .. max_message_receive_rate_past_30_days, output_location)
   output(fname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Bulk size recommendation = " .. bulk_size .. " from " .. hub_probe_path, output_location)

end

main()
