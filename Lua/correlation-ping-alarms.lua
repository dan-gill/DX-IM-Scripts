--------------------------------------------------------------------------------
-- script : correlation-ping-alarms.lua
-- author : Dan Gill
-- March 2020
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- desc   : The intention of this script is to close packet loss alarms from
-- net_connect when a corresponding connection failed alarm exists.
-- This script should be run by the nas on_arrival with arguments passed to it.
-- The only parameter is the message filter to process.

-- The folder "script_logs" *MUST* be manually created under the nas directory
-- prior to running this script.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Set Variables
-----------------------------------------------------------------------
-----------------------------------------------------------------------

-- Where are your require files?
package.path = package.path .. ";./scripts/includes/?.lua"

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
-----------------------------------------------------------------------
-----------------------------------------------------------------------

require ("logging_functions")
require ("error_functions")
require ("table_functions")

local message = ""

if SCRIPT_ARGUMENT ~= nil then
   parms = split(SCRIPT_ARGUMENT)
   for k,v in ipairs (parms) do
      if k == 1 then
         message = v
      end
   end
end

local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
local script_short_name = left (SCRIPT_NAME, str_beg-1)

-- Closes alarm by alarm_id
local function close_alarm(nimid, acked_by)
   local args = pds.create ()
   pds.putString (args, "nimid", nimid)
   pds.putString (args, "by", acked_by)

   nimbus.request("nas", "close_alarms", args)
   pds.delete(args)
end

-- Grabs any alarms using correlation by source, probe, origin, and message
local function get_correlated_alarms(source, probe, message, origin)
   local al = alarm.list("source", source, "prid", probe, "origin", origin,
      "message", "%" .. message .. "%")

   return al
end

local function main()
   local a = alarm.get()
   local al = get_correlated_alarms(a.source, a.prid, message, a.origin)

   if al ~= nil then
      close_alarm(a.nimid, script_short_name)
   end

end

main()
