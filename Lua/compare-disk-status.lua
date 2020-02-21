---------------------------------------------------------------------------------------------------
-- script : compare-disk-status.lua
-- author : Dan Gill
-- January 2019
-- version: 2.01
---------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------
-- desc   : The intention of this script is to email a list of SQL commands for drives
-- added/removed.
-- This script should be run by the nas with arguments passed to it. The only parameter
-- is the hub name to process or ALL for all hubs.
-- Alternatively, the script may be run manually and will use the variables provided in the script.
-- The folder "script_logs" *MUST* be manually created under the nas directory prior to running this
-- script.
---------------------------------------------------------------------------------------------------        
---------------------------------------------------------------------------------------------------
-- Version  | Details
---------------------------------------------------------------------------------------------------
-- 1.0      | Initial Version
-- 1.1      | 1/31/2019 - Added hubs and drives to exclude hash tables to skip certain hubs and
--            robot/drive combinations from processing.
-- 1.2      | 2/7/2019 - Changed email to indicate when file is empty.
-- 1.3      | 2/13/2019 - Replaced for loop for disk check with hash table in get_disk_status.
-- 1.4      | 2/15/2019 - Added regular expression testing to eliminate robots from processing
-- 1.5      | 6/11/2019 - Removed clustered disks from output by adding them to exclude table
-- 1.6      | 6/17/2019 - Remove robots from lookup that aren't in CM_NIMBUS_ROBOT
-- 1.7      | 6/21/2019 - Excluded FileSystemType CSVFS - Cluster drives
-- 1.8      | 7/17/2019 - Simplified cluster check. Also added output for error robot.
-- 1.9      | 7/18/2019 - Fixed FileSystemType CSVFS check.
-- 2.00     | 12/19/2019 - Added Brian Nelson to distribution list
-- 2.01     | 01/09/2020 - Added database.close() commands.
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

local hub = "dagbur-nshub101" -- Specify hub (hub name only, full path isn't needed) or ALL
local recipients = "asurati@gocloudwave.com,bnelson@gocloudwave.com,degts@gocloudwave.com,dgill@gocloudwave.com,rgaines@gocloudwave.com"
local output_location = 2 -- 1 = stdout; 2 = file; 3 = both
-- Hash table of hubs that should not be processed
local hubs_to_exclude = {
   ["reo-nshub01"] = true,
}
-- Input regex to match, later if statement will NOT the result for exclusion
local regex_exclusion = ""
-- Hash table of robot/drive combos that should not be processed
local drives_to_exclude = {
   ["/NMS/mru-nshub01/filestore"] = {["F"] = true,}, -- Removed per John Duffy (300-84765) and Jim Salvas (300-86356)
   ["/NMS/ohmt-nshub01/m001-rm01"] = {["Z"] = true,}, -- Removed per Pete Davagian email "Disk Monitoring for OHMT servers" on 6/13/2019
   ["/NMS/deb-nshub01/deb-rm01"] = {["E"] = true,}, -- Removed per 100-15443
   ["/NMS/gej-nshub01/gej-fs01"] = {["O"] = true,}, -- Removed per 500-12147
   ["/NMS/glm-nshub01/glm-met"] = {["E"] = true,}, -- Removed per Tony Ackley email "<GLM> Mee Memorial -" on 7/8/2019
   ["/NMS/mhjv-nshub01/mhjv-scaimage"] = {["S"] = true, ["T"] = true,}, -- Removed per 200-9593
   ["/NMS/maj-nshub01/maj-wi-was13"] = {["D"] = true,}, -- Removed per Task 500-14396 11/13/2019
   ["/NMS/hae-nshub01/hhhapps6"] = {["D"] = true,}, -- Removed per Task 500-14396 11/13/2019
   ["/NMS/sge-nshub01/sge-sca1"] = {["R"] = true, ["S"] = true,},
-- This is the block of BU servers with drives that should not be monitored per Jim Salvas on 2/15/2019
   ["/NMS/wmi-nshub01/ohos-wmi-bu01"] = {["E"] = true,},
   ["/NMS/hae-nshub01/ohos-hae-bu01"] = {["X"] = true,},
   ["/NMS/hoh-nshub01/ohos-hoh-bu01"] = {["Z"] = true,},
   ["/NMS/riu-nshub01/ohos-riu-bu01"] = {["E"] = true, ["R"] = true,},
   ["/NMS/TXOS-NSRELAY01/txos-hdlc-bu01"] = {["X"] = true,},
-- End block of BU servers
}
local query = "select D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X ,Y, Z from disk_monitoring_lookup where robot_address = '"
local delete_old_robots = "delete from disk_monitoring_lookup where robot_address not in (select address from CM_NIMBUS_ROBOT);"


-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- DO NOT EDIT BELOW THIS LINE
-----------------------------------------------------------------------
-----------------------------------------------------------------------

require ("logging_functions")
require ("error_functions")
require ("table_functions")

if SCRIPT_ARGUMENT ~= nil then
   parms = split(SCRIPT_ARGUMENT)
   for k,v in ipairs (parms) do
      if k == 1 then
         hub = v
      end
   end
end

-- Find first period in script name
local str_beg, str_end = string.find (SCRIPT_NAME,".",1,true)
-- Create log file name up to the first period (excluded .lua from name)
local logfname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) .. "-" .. hub .. ".log"
-- Create SQL file name up to the first period (excluded .lua from name)
local sqlfname = "./script_logs/" .. left (SCRIPT_NAME, str_beg-1) .. "-" .. hub .. ".sql"

----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Get UIM robot details
-----------------------------------------------------------------------
-----------------------------------------------------------------------

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

-- Return a list of all robots under a hub
local function get_robotlist(hub_addr)

   local robots, rc = nimbus.request(hub_addr, "getrobots")
   if rc == NIME_OK then -- If command successful, return robotlist
      if robots.robotlist ~= nil then
         return robots.robotlist, rc
      else
         return nil, 110 -- Return code 110 for empty list
      end
   else -- If command fails, log error and code
      output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." FATAL: Error running getrobots callback against hub: " .. hub_addr, output_location)
      codes_file(rc,logfname,output_location)
      return nil, rc
   end
  
end

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Pull disk info from robot
-----------------------------------------------------------------------
-----------------------------------------------------------------------

local function get_disk_status(robot_addr)
   -- Create list of disks to process
   local disks = {
      ["D"]=1,["E"]=1,["F"]=1,["G"]=1,["H"]=1,["I"]=1,["J"]=1,
      ["K"]=1,["L"]=1,["M"]=1,["N"]=1,["O"]=1,["P"]=1,["Q"]=1,["R"]=1,["S"]=1,
      ["T"]=1,["U"]=1,["V"]=1,["W"]=1,["X"]=1,["Y"]=1,["Z"]=1
                 }

   -- Start with all disks set to no monitoring
   local robot_disks = { ["robot_addr"] = robot_addr, ["D"]=0,["E"]=0,["F"]=0,["G"]=0,["H"]=0,["I"]=0,["J"]=0,
                         ["K"]=0,["L"]=0,["M"]=0,["N"]=0,["O"]=0,["P"]=0,["Q"]=0,["R"]=0,["S"]=0,
                         ["T"]=0,["U"]=0,["V"]=0,["W"]=0,["X"]=0,["Y"]=0,["Z"]=0
                       }
   -- Start with all disks set to local
   local cluster_disks = {["D"]=0,["E"]=0,["F"]=0,["G"]=0,["H"]=0,["I"]=0,["J"]=0,
                         ["K"]=0,["L"]=0,["M"]=0,["N"]=0,["O"]=0,["P"]=0,["Q"]=0,["R"]=0,["S"]=0,
                         ["T"]=0,["U"]=0,["V"]=0,["W"]=0,["X"]=0,["Y"]=0,["Z"]=0
                       }
   
   local skip = 1 -- Use this to skip output if no drives found other than C:\

   local disk_status, rc = nimbus.request(robot_addr .. "/cdm", "disk_status")
   
   if rc == NIME_OK then -- If disk_status command is successful
      local disk_status_data = disk_status.data -- truncate data table to necessary components

      local cluster_info, rc_cluster = nimbus.request(robot_addr .. "/cdm", "cluster_info")
      
      if rc_cluster == NIME_OK then -- If cluster_info command is successful
         local cluster_disk = cluster_info.disk -- truncate data table to necessary components

         if cluster_disk ~= nil then -- If there are clustered disks
            for k,_ in pairs (cluster_disk) do
               cluster_disks[left(cluster_disk[k].filesys, 1)] = 1 -- Mark clustered disks
            end
         end
      end
      
      -- Make sure data table isn't empty
      if disk_status_data ~= nil then
         -- Added to troubleshoot why clustered disks are appearing for this server
         -- if robot_addr == "/NMS/ohmt-nshub01/ohmt-hvc008" then
            -- tdump_file(disk_status_data, logfname, output_location)
         -- end
         
         for k,_ in pairs (disk_status_data) do -- Cycle through all disks on robot

            if drives_to_exclude[robot_addr] ~= nil then -- See if robot is in exclude list
               -- If robot is in exclude list, then make sure drive isn't in exclude list
               if (not drives_to_exclude[robot_addr][left(disk_status_data[k].FileSys, 1)]) and cluster_disks[left(disk_status_data[k].FileSys, 1)] == 0 and disks[left(disk_status_data[k].FileSys, 1)] == 1 and disk_status_data[k].FileSystemType ~= "CSVFS" then
                  robot_disks[left(disk_status_data[k].FileSys, 1)] = 1
                  -- Skip is set to 0 to indicate that matching drives were found and output will be returned
                  skip = 0
               end
            -- Process all drives since robot isn't in exclude list
            else
               if disks[left(disk_status_data[k].FileSys, 1)] == 1 and cluster_disks[left(disk_status_data[k].FileSys, 1)] == 0 and disk_status_data[k].FileSystemType ~= "CSVFS" then
                  robot_disks[left(disk_status_data[k].FileSys, 1)] = 1
                  -- Skip is set to 0 to indicate that matching drives were found and output will be returned
                  skip = 0
               end
            end
         end
      end
      
      if skip == 0 then -- Return findings
         return robot_disks, rc
      else -- Return nil if nothing should be done
         return nil, 120 -- Using return code 120 for skipping output
      end
   end
   
   -- Return nil because callback failed
   return nil, rc
   
end

-----------------------------------------------------------------------
-----------------------------------------------------------------------
-- Pull disk info from table
-----------------------------------------------------------------------
-----------------------------------------------------------------------

local function check_table_data(fquery)
   database.open("provider=nis;database=nis;driver=none")
   
   local result,rc,err = database.query(fquery)
   database.close()
   
   if rc == NIME_OK then
      return result[1] -- Return table from DB query
   else
      return nil
   end
   
end

local function delete_old_records(fquery)
   database.open("provider=nis;database=nis;driver=none")
   
   local result,rc,err = database.query(fquery)
   database.close()
   
   if rc == NIME_OK then
      return rc -- Return table from DB query
   else
      return nil
   end
   
end

-- Email a file
local function email_file(to, subject, path)
   local stats = file.stat(path)
   
   if stats.size > 0 then
      local buf = file.read(path, "r")
      action.email(to, subject, buf)
   else
      action.email(to, subject, "File was empty.")
   end
end

local function main()
   -- Creates/overwrites the file - only do once
   if output_location == 2 or output_location == 3 then
      file.create (logfname)
      file.create (sqlfname)
   end

   output(logfname,timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Checking disk status on hub(s): " .. hub ..  ".", output_location)
   output(sqlfname,"-- Do not process any clustered servers in this list. If a clustered server appears in this list, deploy the cluster probe and manually configure both it and the cdm probe in AC or IM.", output_location)
   output(sqlfname,"-- If you installed a robot recently on a non-clustered server in this list, run the SQL command for that server.", output_location)
   output(sqlfname,"-- Process all non-clustered pre-existing servers by running the listed commands.", output_location)

   -- Delete old records from lookup table
   -- local rc_delete_records = delete_old_records(delete_old_robots)

   -- Get all hubs as seen from nas running this script
   local hublist, rc_hubs = get_hublist()

   if rc_hubs == NIME_OK then -- If command was successful
      for k,_ in pairs (hublist) do -- Cycle through each hub
         -- Process if hub name matches or if ALL hubs specified to process
         -- Exclude any hubs that are in the hubs_to_exclude hash table
         if (hub == hublist[k].name or hub == "ALL") and not hubs_to_exclude[hublist[k].name] then
            local robotlist, rc_robots = get_robotlist(hublist[k].addr) -- Get list of robots
            if rc_robots == NIME_OK then -- If command was successful
               for key,_ in pairs (robotlist) do -- Cycle through each robot
                   -- Skip hubs, skip robots that are in exclude all list, and make sure robot status is OK
                  if hublist[k].robotname ~= robotlist[key].name and drives_to_exclude[robotlist[key].addr] ~= "ALL" and robotlist[key].status == NIME_OK and not regexp(robotlist[key].name, regex_exclusion) then
                     -- Run probe callback to obtain list of disks found
                     local robot_details, rc_details = get_disk_status(robotlist[key].addr)
                     -- Run DB query to get current lookup table details for specific robot (only one row should be returned)
                     local table_details = check_table_data(query .. robotlist[key].addr .. "'")
                     -- Check that probe callback returned a table
                     if rc_details == NIME_OK and robot_details ~= nil then
                        -- Check that DB query returned a table 
                        if table_details ~= nil then
                           local set_disks = nil
                           for k_disk, _ in pairs (table_details) do -- Cycle through each drive letter from DB
                              -- If callback and table values don't match, provide SQL query that will create a match
                              if robot_details[k_disk] ~= table_details[k_disk] then
                                 if set_disks == nil then
                                    set_disks = k_disk .. " = " .. robot_details[k_disk]
                                 else
                                    set_disks = set_disks .. ", " .. k_disk .. " = " .. robot_details[k_disk]
                                 end
                              end
                           end
                           if set_disks ~= nil then
                              output(sqlfname, "update disk_monitoring_lookup set " .. set_disks .. " where robot_address = '" .. robotlist[key].addr .. "'; -- Updates a robot that has multiple drives already.", output_location)
                           end
                        else -- If DB query didn't return a table then a record may need to be added to the DB
                           output(sqlfname, "insert into disk_monitoring_lookup values ('" .. robotlist[key].addr .. "', '" .. robot_details["D"] .. "', '" .. robot_details["E"] .. "', '" .. robot_details["F"] .. "', '" .. robot_details["G"] .. "', '" .. robot_details["H"] .. "', '" .. robot_details["I"] .. "', '" .. robot_details["J"] .. "', '" .. robot_details["K"] .. "', '" .. robot_details["L"] .. "', '" .. robot_details["M"] .. "', '" .. robot_details["N"] .. "', '" .. robot_details["O"] .. "', '" .. robot_details["P"] .. "', '" .. robot_details["Q"] .. "', '" .. robot_details["R"] .. "', '" .. robot_details["S"] .. "', '" .. robot_details["T"] .. "', '" .. robot_details["U"] .. "', '" .. robot_details["V"] .. "', '" .. robot_details["W"] .. "', '" .. robot_details["X"] .. "', '" .. robot_details["Y"] .. "', '" .. robot_details["Z"] .. "'); -- This is either a new robot or the first time a drive other than C:\ is being added to the device.", output_location)
                        end
                     elseif rc_details == 120 then -- No other drives discovered
                        if table_details ~= nil then -- However, record is in disk_monitoring_lookup table
                           output(sqlfname, "delete from disk_monitoring_lookup where robot_address = '" .. robotlist[key].addr .. "'; -- Delete from DB since only a C:\\ drive should be monitored.", output_location)
                        end
                     else -- Callback failed for cdm probe, output result
                        output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." WARN: Error running cdm callback against robot: " .. robotlist[key].addr, output_location)
                        codes_file(rc_details,logfname,output_location)
                     end
                  end
               end
            end
         end
      end
   end
   
   output(logfname, timestamp.format ( timestamp.now(), "%Y-%m-%d %H:%M:%S").." INFO: Script has completed running.", output_location)
   email_file(recipients, left (SCRIPT_NAME, str_beg-1) .. "-" .. hub, sqlfname)
   
end

main()