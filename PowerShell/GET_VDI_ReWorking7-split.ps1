<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2019 v5.6.160
	 Last Updated:  11/14/19  1:05 PM
	 Created by:   	RGaines
	 Organization: 	Cloudwave, Inc.
	 Filename:     	GET_VDI-Reworking7.ps1
	===========================================================================
	.DESCRIPTION
		Script retrieves statistics, and health statuses from the following components:
			- View Pool
			- Connection Broker
			- VC Broker
			- AD
			- UAG
		and writes report to log file.

	.PARAMETER UAGServer
    Specifies the ipAddr of the UAG server.

	.PARAMETER UAGUser
	Specifies the login username of the UAG server.

	.PARAMETER
	Specifies the login password of the UAG server.

	.INPUTS
	None

	.OUTPUTS
	None

	. NOTES
	The script performs several envionmental checks:
		- Check-FIPS				Check to see if FIPS is Enabled.  FIPS blocks communication to View 7 components vis Powershell
									Id enables, script ends.  FIPS must then be disabled manally and the server rebooted.
		- Check-PowerCLI			Checks to see if the PowerCLI module is loaded, and loads it if it is not.
		- Check-VMware.Viw.Broker	Checks to see if the VMware.View.Broker module is loaded, amd loads it if it is not.
		- Check-OSVersion			Displays OS version in the report
		- Checl-PSVersion			Displays PS version in the report

	.EXAMPLE

	PS> Get_VDI_Working7 -UAGServer1 <servername> -UAGuser <username> -UAGpswd <password>

	.UPDATES

	11/14/2019	Add support to included DELETING status to Preparing count.  Reference $delete
#>


#---------------------------------------------------------- FUNCTION DECLARATIONS --------------------------------------------------------------------------
function Check-PowerCLI()
{
<# Notes:  
	Installs VMware PowerCLI if module is not loaded
#>
	
	if (Get-Module -ListAvailable -Name VMware.PowerCLI)
	{
		Write-Output ("Check: VMware PowerCLI Module: Installed")
	}
	else
	{
		Write-Output ("Check: VMware PowerCLI Module: Not Installed")
		Write-Output ("Installing Missing Module...")
		Install-Module -Name VMware.PowerCLI -Force
	}
}

function Check-VWWareViewBroker()
{
<# Notes:
	Installs VMware View Broker if module is not loaded
#>
	
	if (Get-Module -ListAvailable -Name VMware.View.Broker)
	{
		
		Write-Output ("Check: Vmware.View.Broker Module: Installed")
	}
	else
	{
		Write-Output ("Check: Vmware.View.Broker Module: Not Installed")
		Write-Output ("Installing Missing Module...")
		Import-Module -Name VM*
	}
	
}

function Check-FIPSEnabled()
{
<# Notes:
	Checks to see if FIOS is enable.  If enabled, FIP will need to be disabled and the server rebotted
#>	
	
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy'
    
    if ($PSVersionTable.PSVersion.Major -eq 5)  {
    	$value = (Get-ItempropertyValue -Path $key -Name Enabled).Enabled
	}
    
    if ($PSVersionTable.PSVersion.Major -eq 4)  {
        $value =  (Get-ItemProperty -Path $key -Name Enabled).Enabled
    }
	return $Value
}

function Get-Hostname ()
{
<# Notes:
	Checks OS Version
#>	
	$hostname = $(hostname)
	
	return $hostname
}

function Check-OSVersion ()
{
<# Notes:
	Checks OS Version
#>	
	$sOS = Get-WmiObject -class Win32_OperatingSystem
	
	return $sOS.Caption
}

function Check-PsVersion ()
{
	
	$major = $PSVersionTable.PSVersion.Major.ToString()
	$minor = $PSVersionTable.PSVersion.Minor.ToString()
	$build = $PSVersionTable.PSVersion.Build.ToString()
	$revision = $PSVersionTable.PSVersion.Revision.ToString()
	
	if ($build -eq "-1") { $build = "0" }
	if ($revision -eq "-1") { $revision = "0" }
	
	$myVer = $($major) + "." + $($minor) + "." + $($build) + "." + $($revision)
	
	return $myVer
}

function Perform-EnvChecks()
{
	
    Write-Output ("=======================================")
    Write-Output ("System Pre-Checks")
    Write-Output ("=======================================")
    # Get Hotname
	$Hostname = Get-Hostname
	Write-Output ("ConServer: $Hostname")
	
	# Check 1.  Get OS Version
	$OSVersion = Check-OSVersion
	Write-Output ("Check: $OSVersion")
	
	# Check 2. Powershell Version
	$PSVersion = Check-PsVersion
	Write-Output ("Check: PSVersion $PSVersion")
	
	#3 Check 3.  Is FIPS Enabled  
	$FIPS = Check-FIPSEnabled
	If ($FIPS -eq 1)
	{
		Write-Output ("Check: FIPS Enabled")
		Exit (-1)
	}
	else
	{
		Write-Output ("Check: FIPS Disabled")
	}
	
	# Check 4.  is PowerCLI Installed
	Check-PowerCLI
	
	# Check 5.  Is Vmware.View.Broker Installed
	Check-VWWareViewBroker

    Write-Output ("=======================================")
    Write-Output ("End of System Pre-Checks               ")
    Write-Output ("=======================================")
	
}

function Set-VarsAndLogging()
{
	$ConfirmPreference = "High"
	$DebugPreference = "Continue"
	$VerbosePreference = "Continue"
	$ErrorActionPreference = "Continue"
	
	$ScriptPath = "C:\Scripts\VDI\optimization.ps1"
	$ScriptFolder = Split-Path $ScriptPath -Parent
	$LogName = "optimization.log"
	$LogFullPath = Join-Path -Path $ScriptFolder -ChildPath $LogName
	
	Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -ErrorAction $ErrorActionPreference
	Set-Location $ScriptFolder
	
	$ErrorActionPreference = "SilentlyContinue"
	Stop-Transcript | Out-Null
	$ErrorActionPreference = "Continue"
	Start-Transcript -Path $LogFullPath -append -force
}

# Set Environment Vars and Logging
Set-VarsAndLogging

# Perform Environment Checks
Perform-EnvChecks

#Adds ViewManager plugin
Add-PSSnapin VMware.View.Broker

#Defines Date Format
$startTime = Get-Date
$date = Get-Date -format g
$vmdate = ((get-date).AddDays(-1)).tostring()

#Defines variables used in the script
$ViewServer = "localhost"

#Specify the LDAP path to bind to
$LDAPPath = 'LDAP://' + $viewServer + ':389/DC=vdi,DC=vmware,DC=int'
$LDAPEntry = New-Object DirectoryServices.DirectoryEntry $LDAPPath

#Create a selector and start searching from the path specified in $LDAPPath for Pools
$Selector = New-Object DirectoryServices.DirectorySearcher
$Selector.SearchRoot = $LDAPEntry

#Find all available pools
$object = "pae-serverpooltype"
$Pool_ID = "cn"
#$Pools = $Selector.FindAll() | where {$_.Properties.objectcategory -match "CN=pae-ServerPool" -and $_.Properties.$Pool_ID -notlike "*Test*" -and $_.Properties.$object -eq "4"} 
$Pools = $Selector.FindAll() | where { $_.Properties.objectcategory -match "CN=pae-ServerPool" -and $_.Properties.$Pool_ID -and $_.Properties.$object -eq "18" }

###################
#Beinging of Report#
####################

#Outputs DateTime stamp to script output
Write-Output (" ")
Write-Output ("Report Date: " + $date)

#Baseline - number of ppols found.  Not used anywhere else
$count = $pools.count


Write-Output (" ")
Write-Output (" ")
Write-Output ("=======================================")
Write-outPut ("Checking Pools                         ")
Write-Output ("=======================================")

#Gather Pool Info
Foreach ($Pool in $Pools)
{
	#"agentErrorText = OK"
	$attribute = $Pool.Properties
	
	# Define what value we are looking for
	$value = 'name'
	$status = 'pae-vmprovenabled'
	$msg = 'pae-vmproverror'
	$PoolMembers = "pae-memberdn"
	$Pool = $attribute.$value
	$PoolProvState = $attribute.$status
	$PoolError_msg = $attribute.$msg
	$PoolVMs = $attribute.$PoolMembers
	
	#Get Desktop Connection State
	$RemoteSessions = @(Get-RemoteSession -pool_id $Pool -ErrorAction SilentlyContinue)
	$RSessDNS = @($RemoteSessions | select DNSname -ErrorAction SilentlyContinue)
	$connected = @(Get-RemoteSession -pool_id $Pool -ErrorAction SilentlyContinue | where { $_.state -eq "Connected" } -ErrorAction SilentlyContinue).count
	$disconnected = @(Get-RemoteSession -pool_id $Pool -ErrorAction SilentlyContinue | where { $_.state -eq "Disconnected" } -ErrorAction SilentlyContinue).count
	$RemoteSessCount = $RemoteSessions.count
	$PoolVMsCount = $PoolVMs.count
	$VCenterVMs = @(get-desktopvm -pool_id $pool | select Name, IPaddress)
	
	
	#Create a selector and start searching from the path specified in $LDAPPath for VMs
	$VMname = "pae-displayname"
	$VMs = $Selector.FindAll() | where { $_.Properties.objectcategory -match "CN=pae-VM" -and $_.Properties.$VMname } #-notlike "*test*"
	
	clear-variable dirty, notdirty, ready, clone, maint, provisioned, delete, cust, maintdays, probvms, prepvms, IPMismatch, VcenterIP, FwdNSL, DnsIP, result, PrepParms, PrepvCenterNoIP -ErrorAction SilentlyContinue
	clear-variable agentdisabled, AlreadyUsed, AgentUnreachable, DHCPErrors, available, PrepIPdiff, TestConn, PrepNoICMP, noICMP, Refreshing -ErrorAction SilentlyContinue
	clear-variable ProbDesktops, PreparedforUse, ProvisionedDesktops, Preparing, PercentUtilized, PercentAvailable, PercentInError, testconn, DNSerrors -ErrorAction SilentlyContinue
	
	$ProbUsed = $null
	$ProbUsed = @{ }
	$ProbUnReach = $null
	$ProbUnReach = @{ }
	$ProbDisabled = $null
	$ProbDisabled = @{ }
	$ProbDHCP = $null
	$ProbDHCP = @{ }
	
	$PrepMaint = $null
	$PrepMaint = @{ }
	$PrepOther = $null
	$PrepOther = @{ }
	$PrepUnReach = $null
	$PrepUnReach = @{ }
	$PrepNoICMP = $null
	$PrepNoICMP = @{ }
	$PrepIPdiffV2 = $null
	$PrepIPdiffV2 = @{ }
	$PrepDHCP = $null
	$PrepDHCP = @{ }
	$PrepvCenterNoIP = $null
	$PrepvCenterNoIP = @{ }
	$PrepDNS = $null
	$PrepDNS = @{ }
	
	#Gather VM Info
	ForEach ($VM in $VMs)
	{
		$attribute = $VM.Properties
		
		#Define VM values
		$VMPool = 'pae-memberdnof'
		$value = "pae-dirtyfornewsessions"
		$state = "pae-vmstate"
		$DN = "distinguishedname"
		$DNSname = "iphostnumber"
		$OpFlags = "pae-svivmoperationflags"
		$refreshed = "pae-svivmrefreshed"
		$VMpath = 'pae-vmpath'
		$CN = "cn"
		
		#VM Pool Membership
		$VMmember = $attribute.$VMPool
		#VM Name
		$VM_name = $attribute.$VMname
		#VM Availability
		$VMProvStatus = $attribute.$value
		#VM State
		$VMstate = $attribute.$state
		#VM Distinguishedname
		$VMDN = $attribute.$DN
		#VM FQDN
		$VMDNS = $attribute.$DNSname
		# VMAD CN
		$VMCN = $attribute.$CN
		#VM OpFlags
		$Flags = $attribute.$OpFlags
		$vmrefresh = $attribute.$refreshed
		#Format date for comparision to last refresh
		$refreshdate = $($vmrefresh).tostring()
		$timediff = New-TimeSpan $refreshdate $date
		$daysdiff = $timediff.TotalDays
		
		$Found = 0
		$error.clear()
		$AgentCheck = " "
		$version = " "
		#$AgentOK = '.*agentErrorText.*=.*OK.*'
		$AgentError = '.*agentErrorCode.*=.*ffffffff.*'
		$AgentOK = '.*agentErrorCode* = 0'
		$DHCPProb = '169.254.*.*'
		#$AgVer = '.*Pool:.*'
		
		If ($VMmember -match "CN=$($Pool),")
		{
			#write-output("Desktop: " + $VM_name + "-" + $vmrefresh + "-" + $vmstate + "-" + $VMProvStatus + " -"  + $VMDN)    
			
			#Checks VM Availability
			if ($VMProvStatus -eq "1")
			{
				$dirty++
				#vdmadmin -M -m $($vm_name)
				if ($RSessDNS -match $VMDNS)
				{ $found = 1 }
				if (-not ($Found))
				{
					$problemdesktop++
					#write-output("Desktop: " + $VM_name + "-" + $vmrefresh + "-" + $vmstate + "-" + $VMDN)   
					$VcenterIP = ($VCenterVMs | where { $_.name -eq $($vm_name) } | select -ExpandProperty ipAddress)
					if ($VcenterIP -eq "")
					{
						$agentunreachable++
						$vcenterIP = "Not Found"
						$PrepParms = ("AD CN: " + $vmcn + "   vCenterIP: " + $vcenterIP).tostring()
						$ProbUnReach.add($vm_name, $PrepParms)
					} #Close of AgentUnreachable
					elseif ($AgentCheck = vdmadmin.exe -A -d $($Pool) -m $($VM_name) -getstatus)
					{
						#write-output("AlreadyUsed - " + $vm_name + "-  AgentCheck: " + $agentcheck)
						if ($AgentCheck -match $AgentOK)
						{
							$AlreadyUsed++
							#write-output("AlreadyUsed - " + $vm_name + "-  VMDN: " + $vmdn)
							$PrepParms = ("AD CN: " + $vmcn).tostring()
							$ProbUsed.add($vm_name, $PrepParms)
						} #Close AlreadyUsed
					}
					elseif ($daysdiff -gt 1)
					{
						$agentdisabled++
						#write-output("AgentDisabled - " + $vm_name + "-  VMDN: " + $vmdn)
						$PrepParms = ("AD CN: " + $vmcn).tostring()
						$ProbDisabled.add($vm_name, $PrepParms)
					}
					else
					{
						$VcenterIP = ($VCenterVMs | where { $_.name -eq $($vm_name) } | select -ExpandProperty ipAddress)
						if ($VcenterIP -match $DHCPProb)
						{
							$DHCPErrors++
							# write-output("DHCPError - " + $vm_name + "-  VMDN: " + $vmdn)
							$PrepParms = ("vCenterIP: " + $VCenterIP).tostring()
							$ProbDHCP.add($vm_name, $PrepParms)
						} #Close of DHCP Probs
					} #close of IP Check     
				} #Close of notFound 
			} #close of Dirty
			else
			{
				$notdirty++
				#vdmadmin -M -m $($vm_name)
				if ($VMProvStatus -eq "<not set>")
				{ $provisioned++ }
				elseif ("$VMstate" -eq "CUSTOMIZING")
				{ $cust++ }
				elseif ("$VMstate" -eq "DELETING")
				{ $delete++ }			
				elseif ("$VMstate" -eq "CLONING")
				{ $clone++ }
				elseif ("$VMstate" -eq "MAINTENANCE")
				{
					$maint++
					#$PrepVMs="MaintMode: " + $vm_name + "  VMDN: " + $vmdn          
					if ($daysdiff -gt 1)
					{
						$maintdays++
						#write-output("MaintMode >24Hours - " + $vm_name + "-  VMDN: " + $vmdn)
						$PrepParms = ("   AD CN: " + $VMCN).tostring()
						$PrepMaint.add($vm_name, $PrepParms)
						#$PrepMaint.add($vm_name,$vmdn)
					}
				} #close of Maint
				elseif ("$VMstate" -eq "READY")
				{
					#Captures DNS Resoultion for current VM
					$FwdNSL = nslookup $vm_name
					if ($error.count -ne 0)
					{ $DnsIP = "Not Found" }
					else
					{ $DnsIP = ($FwdNSL[4].tostring()).TrimStart("Address:  ") }
					
					#Captures IP assigned for current VM as known by vCenter
					$VcenterIP = ($VCenterVMs | where { $_.name -eq $($vm_name) } | select -ExpandProperty ipAddress)
					
					#Compares vCenter IP to Reverse DNS Resoultion for current VM      
					$result = $VcenterIP.CompareTo($DnsIP)
					if ($result -ne 0)
					{
						if ($VcenterIP -like $DHCPProb)
						{
							$DHCPErrors++
							#write-output("DHCPError - " + $vm_name + "-  VMDN: " + $vmdn)
							$PrepParms = ("vCenterIP: " + $VCenterIP + "   DNS_IP: " + $DnsIP).tostring()
							$PrepDHCP.add($vm_name, $PrepParms)
						} #Close of DHCP Error
						elseif ($VcenterIP -eq "")
						{
							$Refreshing++
							$vcenterIP = "Not Assigned Yet - Possibly refreshing Desktop"
							$PrepParms = ("vCenterIP: " + $VCenterIP + "   DNS_IP: " + $DnsIP).tostring()
							$PrepvCenterNoIP.add($vm_name, $PrepParms)
						} #Close of Refreshing
						elseif ($DNSIP -like "Not Found")
						{
							$DNSErrors++
							#write-output("DHCPError - " + $vm_name + "-  VMDN: " + $vmdn)
							$PrepParms = ("vCenterIP: " + $VCenterIP + "   DNS_IP: " + $DnsIP).tostring()
							$PrepDNS.add($vm_name, $PrepParms)
						} #Close of DNS Error
						else
						{
							$IPMismatch++
							#write-output("IPMismatch-Host: " + $vm_name + "   VMIP: " + $VCenterIP + '   DNS: ' +$DnsIP)
							$PrepParms = ("vCenterIP: " + $VCenterIP + "   DNS_IP: " + $DnsIP).tostring()
							$PrepIPdiffV2.add($vm_name, $PrepParms)
						} #Close IPMismatch
					}
					else
					{
						$TestConn = test-connection -ComputerName $($vm_name) -Count 2 -Quiet -EA SilentlyContinue
						if ($TestConn -match 'True')
						{ $ready++ }
						else
						{
							$noICMP++
							$PrepParms = ("vCenterIP: " + $VCenterIP + "   DNS_IP: " + $DnsIP).tostring()
							$PrepNoICMP.add($vm_name, $PrepParms)
						} #close of ICMP
					} #Close of Test Connection
				} #close of Ready  
			} #Close of notDirty
		} #close of pool check          
	} #close of each vm   
	
	
	#Perform Session Calculations
	if ($AlreadyUsed -eq $null)
	{ $AlreadyUsed = 0 }
	
	if ($AgentUnreachable -eq $null)
	{ $AgentUnreachable = 0 }
	
	if ($agentdisabled -eq $null)
	{ $agentdisabled = 0 }
	
	if ($DHCPErrors -eq $null)
	{ $DHCPErrors = 0 }
	
	if ($maintdays -eq $null)
	{ $maintdays = 0 }
	
	if ($cust -eq $null)
	{ $cust = 0 }
	
	if ($delete -eq $null)
	{ $delete = 0 }
	
	if ($clone -eq $null)
	{ $clone = 0 }
	
	if ($maint -eq $null)
	{ $maint = 0 }
	
	if ($provisioned -eq $null)
	{ $provisioned = 0 }
	
	if ($dirty -eq $null)
	{ $dirty = 0 }
	
	if ($notdirty -eq $null)
	{ $notdirty = 0 }
	
	if ($IPMismatch -eq $null)
	{ $IPMismatch = 0 }
	
	if ($NoICMP -eq $null)
	{ $NoICMP = 0 }
	
	if ($Refreshing -eq $null)
	{ $Refreshing = 0 }
	
	if ($DNSErrors -eq $null)
	{ $DNSErrors = 0 }
	
	$ProbDesktops = $AlreadyUsed + $AgentUnreachable + $agentDisabled + $DHCPErrors
	$PreparingProbs = $noICMP + $IPMismatch + $Refreshing + $DNSErrors + $DHCPErrors
	$Preparing = $delete + $cust + $clone + $maint + $PreparingProbs
	$Available = $PoolVMsCount - ($RemoteSessCount + $ProbDesktops + $PreparingProbs)
	$PreparedforUse = $PoolVMsCount - ($ProbDesktops + $PreparingProbs)
	$ProvisionedDesktops = $PreparedforUse - ($RemoteSessCount + $available)
	
# 01/13/2020 - Added if statement for division by 0 errors
	if( $PreparedforUse -eq 0) 
	{$PercentUtilized = 0; $PercentInError = 0;} 
	else {
	$PercentUtilized = [decimal]::Round(($RemoteSessCount/$PreparedforUse) * 100) 
	$PercentInError = [decimal]::Round(($ProbDesktops/$PreparedforUse) * 100)
	}

	$PercentAvailable = 100 - $PercentUtilized - $PercentInError

	Write-Output ("Pool: " + $Pool + ", VMsInPool: " + $PoolVMsCount + ", AvailableVMs: " + $available + ", ConnectedSessions: " + $connected + ", DisconnectedSessions: " + $disconnected + ", SessionsInUse: " + $RemoteSessCount + ", PercentUtilized: " + $PercentUtilized + "%, PercentAvailable: " + $PercentAvailable + "%, Preparing: " + $Preparing + "%, Problem: " + $ProbDesktops)
	
} #Close of pools    

Write-Output ("=======================================")
Write-Output ("End Of Pools                           ")
Write-Output ("=======================================")

#CB Health Status 
$CBMonitorIDs = get-monitor -monitor cbmonitor | Select -ExpandProperty monitor_id

Write-Output (" ")
Write-Output (" ")
Write-Output ("=======================================")
Write-Output ("Connection Broker Health Status        ")
Write-Output ("=======================================")

#Loop through the pools
ForEach ($CBMonitorID in $CBMonitorIDs)
{
	$cbalive = get-monitor -monitor cbmonitor | where { $_.monitor_id -eq $CBMonitorID } | select -ExpandProperty isAlive
	if ($cbalive -like "true")	{ $cbonline = 1 } else 	{ $cbonline = 0 }

	$cbstatusvalues = get-monitor -monitor cbmonitor | where { $_.monitor_id -eq $CBMonitorID } | select -ExpandProperty statusValues
	if ($cbstatusvalues -like "*=ok*")	{ $cbstatus = 1 }	else 	{ $cbstatus = 0 }

	
	Write-Output ("Connection Broker: " + $CBMonitorID + " Online: " + $cbonline + " Status: " + $cbstatus)
	#Write-Output ("Online: " + $cbonline)
	#Write-Output ("Status: " + $cbstatus)
    $num = $num + 1
}
Write-Output ("=======================================")
Write-Output ("End of CB Health Status                ")
Write-Output ("=======================================")

#CB Session Metrics  
$cbcluster = get-monitor -monitor CBMonitor | where { $_.id -like "*-con01" } | select -ExpandProperty clusterid
$cbTotalses = get-monitor -monitor CBMonitor | where { $_.id -like "*-con01" } | select -ExpandProperty totalsessions
$cbTotalHigh = get-monitor -monitor CBMonitor | where { $_.id -like "*-con01" } | select -ExpandProperty totalsessionshigh


Write-Output (" ")
Write-Output (" ")
Write-Output ("=======================================")
Write-Output ("Connection Broker Session Metrics      ")
Write-Output ("=======================================")
Write-Output ("Cluster: " + $cbCluster + ", TotalCurrentSessions: " + $cbTotalses + ", MaxConcurrentSessions: " + $cbTotalHigh)
Write-Output ("=======================================")
Write-Output ("End of CB Session Metrics              ")
Write-Output ("=======================================")

#==========================================================================
#Get Overall Health of all VDI Components
#==========================================================================

#VC Status

$vcurl = get-monitor -monitor vcmonitor | select -ExpandProperty url
$vcServer = ($vcurl  |  Select-String -Pattern "\d{1,3}(\.\d{1,3}){3}" -AllMatches).Matches.Value

$vcstate = get-monitor -monitor vcmonitor | select -ExpandProperty state
if ($vcstate -like "*OK*"){ $vcOK = 1 }else { $vcOK = 0 }

$vcbrokerstatus = get-monitor -monitor vcmonitor | select -ExpandProperty brokerEntry
if ($vcbrokerstatus -like "*status=STATUS_UP*"){ $vcbrokerOK = 1 }else { $vcbrokerOK = 0 }

if ($vcbrokerstatus -like "*statusDescription=Connected*"){ $vcbrokerconnected = 1 }else { $vcbrokerconnected = 0 }

$vccomposer = get-monitor -monitor vcmonitor | select -ExpandProperty isComposerEnabled
if ($vccomposer -like "true"){ $vccomposerOK = 1 }else { $vccomposerOK = 0 }

Write-Output (" ")
Write-Output (" ")
Write-Output ("=======================================")
Write-Output ("VC Health Status                       ")
Write-Output ("=======================================")
Write-Output ("Server: " +$vcServer + " State: " + $vcOK + " Status: " + $vcbrokerOK + " Connected: " + $vcbrokerconnected)
Write-Output ("=======================================")
Write-Output ("End of VC Health Status                ")
Write-Output ("=======================================")

#AD Status
$ADMonitorIDs = get-monitor -monitor domainmonitor | Select -ExpandProperty monitor_id
Write-Output (" ")
Write-Output (" ")
Write-Output ("=======================================")
Write-Output ("AD Health Status                       ")
Write-Output ("=======================================")

#Loop through the pools
ForEach ($ADMonitorID in $ADMonitorIDs)
{
	$addomain = get-monitor -monitor domainmonitor | where{ $_.monitor_id -eq $ADMonitorID } | select -ExpandProperty domains
	$adstatus = get-monitor -monitor domainmonitor | where{ $_.monitor_id -eq $ADMonitorID } | select -ExpandProperty isProblem
	
    if ($adstatus -eq $false) {$isFalse = 1} else {$isFalse = 0}
    Write-Output ("Server: " + $ADMonitorID + ", AD Status: " + $isFalse)
}
Write-Output ("=======================================")
Write-Output ("End of AD Health Status                ")
Write-Output ("=======================================")


#DB Status
$DBMonitorIDs = get-monitor -monitor dbmonitor | Select -ExpandProperty monitor_id
$dbstate =  get-monitor -monitor dbmonitor | Select -ExpandProperty state
$dbname = get-monitor -monitor dbmonitor | Select -ExpandProperty dbName

if($dbstate -match "CONNECTED"){$idbState = 1} else {$idbState = 0}
Write-Output (" ")
Write-Output (" ")
Write-Output ("=======================================")
Write-Output ("DB Health Status                       ")
Write-Output ("=======================================")
Write-Output ("Database: " + $dbname + " DB State: " + $idbState)
Write-Output ("=======================================")
Write-Output ("End of DB Health Status                ")
Write-Output ("=======================================")

#SG Status
$SGMonitorIDs = get-monitor -monitor sgmonitor| Select -ExpandProperty monitor_id 
Write-Output (" ")
Write-Output (" ")
Write-Output ("==============================")
Write-Output ("Security Gateway Health Status")
Write-Output ("==============================")     
     
     
#Loop through the pools
ForEach ($SGMonitorID in $SGMonitorIDs)
{
    $sgalive = get-monitor -monitor sgmonitor |where{$_.monitor_id -eq $SGMonitorID}| select -ExpandProperty isalive
    if ($sgalive -like "*true*") {$sgonline = 1} else {$sgonline = 0}
                   
    $sgstatus = get-monitor -monitor sgmonitor|where{$_.monitor_id -eq $SGMonitorID}|  select -ExpandProperty statusValues
    if ($sgstatus -like "*ok*") {$sgstatusOK = 1} else  {$sgstatusOK = 0}
                    
    $sgtotsess = get-monitor -monitor sgmonitor|where{$_.monitor_id -eq $SGMonitorID}| select -ExpandProperty totalSessions
    $sgtunnelsess = get-monitor -monitor sgmonitor|where{$_.monitor_id -eq $SGMonitorID}| select -ExpandProperty tunnelSessions
    $sgpcoipsess = get-monitor -monitor sgmonitor|where{$_.monitor_id -eq $SGMonitorID}| select -ExpandProperty PCoIPSessions
    $sgcertvalid = get-monitor -monitor sgmonitor|where{$_.monitor_id -eq $SGMonitorID}| select -ExpandProperty certValid

    if ($sgcertvalid -like "*true*") {$sgcertOK = 1} else {$sgcertOK = 0} 
    
    $sgcertexpire = get-monitor -monitor sgmonitor|where{$_.monitor_id -eq $SGMonitorID}| select -ExpandProperty certAboutToExpire
    if ($sgcertexpire -like "*false*") {$sgcert_expire = 0} else {$sgcert_expire = 1}   
                              
    #Output Security Gateway Status
    Write-Output ("==============================")
    Write-Output ("Security Server: "+ $SGMonitorID + " Online: " + $sgonline + " Status: " + $sgstatusOK + " Total Sessions: " + $sgtotsess + " Cert Valid: " + $sgcertOK + " Cert About to Expire: " + $sgcert_expire)
    Write-Output ("==============================")
}

$stopTime = Get-Date
$compTime = ($stopTime - $startTime).totalminutes

Write-Output (" ")
Write-Output ("Report Duration: " + $compTime)
Write-Output ("Completed: Yes")
