# Filename: enrichment.rb
# QOS_Processor Ruby Script called by Script_Runner.rb
#
# Note: Log levels are [name (log level in qos_processor)]:
#        debug (4) < info (3) < warn (2) < error (1) < fatal (0)
#        (https://guides.rubyonrails.org/v3.2.14/debugging_rails_applications.html#log-levels)
#        The default log level for the qos_processor probe is 2.

require 'java'
lib_path = 'F:/Nimsoft/probes/slm/qos_processor/lib/'
jar_file = lib_path + 'sqljdbc6-6.2.2.jar'

if File.file?(jar_file)

   $logger.info("@@@ Driver jar file exists!")
   require(jar_file)

   #==========Change the following variables according to your needs==========#
   ip="IP or DNS"
   port="1433"
   db="CA_UIM"
   driver="jdbc:sqlserver://"
   driverClass="com.microsoft.sqlserver.jdbc.SQLServerDriver"
   user="USER"
   passwd="PASSWORD"
   vmware_query = "SELECT DISTINCT cma.description, cmao.origin, sqs.source FROM cm_account cma JOIN cm_account_ownership cmao ON cma.account_id = cmao.account_id JOIN CM_DEVICE_ATTRIBUTE cmda ON cmda.dev_attr_value = cma.description JOIN CM_CONFIGURATION_ITEM cmci ON cmda.dev_id = cmci.dev_id JOIN CM_CONFIGURATION_ITEM_METRIC cmcim ON cmci.ci_id = cmcim.ci_id JOIN S_QOS_DATA sqs ON cmcim.ci_metric_id = sqs.ci_metric_id WHERE cmda.dev_attr_key = 'vmware.ResourcePoolvAppPath' AND sqs.source NOT LIKE '[0-9]%' AND sqs.source = '"
   mnemonic_query = "SELECT DISTINCT cmao.origin, cma.name FROM cm_account cma JOIN cm_account_ownership cmao ON cma.account_id = cmao.account_id WHERE LEFT(cma.name, IIF(CHARINDEX(' ', cma.name)>0,CHARINDEX(' ', cma.name)-1,0)) = '"
   #==========================================================================#


   begin
      dbserver=ip+":"+port
      url = driver+dbserver+";databaseName="+db
      java.lang.Class.forName(driverClass, true, java.lang.Thread.currentThread.getContextClassLoader)
      $logger.info("@@@ About to connect...")
      con = java.sql.DriverManager.getConnection(url,user,passwd);

      if con
         $logger.info("@@@ Connection good to "+dbserver)
      else
         $logger.fatal("@@@ Connection failed")
      end

      b = con.create_statement

      case $monitor.probe
      when "vmware"

         vmware_query = vmware_query + $monitor.source + "' AND sqs.target = '" + $monitor.target + "' AND sqs.qos = '" +$monitor.qos + "' AND sqs.robot = '" + $monitor.robot + "';"

         $logger.warn("@@@ Running query: " + vmware_query)
         rs=b.execute_query(vmware_query)

         while(rs.next())
            if(!$monitor.origin.nil?)
               $logger.warn("@@@ Probe: " + $monitor.probe + ", Source: " + $monitor.source + ", Target: " + $monitor.target + ", Old Origin: "+$monitor.origin)
               value=rs.getString("origin")
               $monitor.origin=value
               $logger.warn("@@@ Probe: " + $monitor.probe + ", Source: " + $monitor.source + ", Target: " + $monitor.target + ", New Origin: "+$monitor.origin)
            end
         end

         rs.close
      # Match SNMPcollector and net_connect for ohos-snmp01 or txos-snmp01 ONLY
      when "pollagent","net_connect"
         if ($monitor.robot[/(?:oh|tx)os-snmp01/])
            # Change source to all caps
            # Look for two common naming standards: Starts with C/L/R and a number
            # or starts with three character Mnemonic, then a dash
            case $monitor.source.upcase
            when /^[CLR]\d-/
               mnemonic =  $monitor.source.upcase[/^[CLR]\d-(?<mnemonic>\w{2,3})/, "mnemonic"]
            when /^\w{3}-/
               mnemonic =  $monitor.source.upcase[/^(?<mnemonic>\w{3})-/, "mnemonic"]
            else
               mnemonic = nil
            end

            if (!mnemonic.nil?)
               mnemonic_query = mnemonic_query + mnemonic + "';"
               $logger.warn("@@@ Running query: " + mnemonic_query)
               rs=b.execute_query(mnemonic_query)

               while(rs.next())
                  if(!$monitor.origin.nil?)
                     $logger.warn("@@@ Probe: " + $monitor.probe + ", Source: " + $monitor.source + ", Target: " + $monitor.target + ", Old Origin: "+$monitor.origin)
                     value=rs.getString("origin")
                     $monitor.origin=value
                     $logger.warn("@@@ Probe: " + $monitor.probe + ", Source: " + $monitor.source + ", Target: " + $monitor.target + ", New Origin: "+$monitor.origin)
                  end
               end

               rs.close
            end

         end
      when "url_response"
         if ($monitor.robot[/(?:oh|tx)os-nsmon03/])
            mnemonic =  $monitor.target.upcase[/^(?<mnemonic>\w{3})[_\s]/, "mnemonic"]

            if (!mnemonic.nil?)
               mnemonic_query = mnemonic_query + mnemonic + "';"
               $logger.warn("@@@ Running query: " + mnemonic_query)
               rs=b.execute_query(mnemonic_query)

               while(rs.next())
                  if(!$monitor.origin.nil?)
                     $logger.warn("@@@ Probe: " + $monitor.probe + ", Source: " + $monitor.source + ", Target: " + $monitor.target + ", Old Origin: "+$monitor.origin)
                     value=rs.getString("origin")
                     $monitor.origin=value
                     $logger.warn("@@@ Probe: " + $monitor.probe + ", Source: " + $monitor.source + ", Target: " + $monitor.target + ", New Origin: "+$monitor.origin)
                  end
               end

               rs.close
            end
         end
      end

      con.close
   end
else
   $logger.fatal("@@@ No jar file found! Make sure you have " + jar_file + " file.")
end
