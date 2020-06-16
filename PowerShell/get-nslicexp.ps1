<#PSScriptInfo

.VERSION 1.0

.AUTHOR @dan_gill

.COMPANYNAME gocloudwave.com

.COPYRIGHT 2019

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
04-29-2019: Initial creation

#> 

<#
.SYNOPSIS
   Grabs Netscaler license information via PS
.DESCRIPTION
   Grabs Netscaler license information via PS.
.PARAMETER nsip
   DNS Name or IP of the Netscaler that needs to be configured. (MANDATORY)
.PARAMETER adminaccount
   Netscaler admin account (Default: ***REMOVED***)
.PARAMETER adminpassword
   Password for the Netscaler admin account (Default: ***REMOVED***)
.EXAMPLE
   ./get-NSlicexp -nsip 10.1.1.2
.EXAMPLE
   ./get-NSlicexp -nsip 10.1.1.2 | ft -AutoSize
.EXAMPLE
   ./get-NSlicexp -nsip 10.1.1.2 -adminaccount nsadmin -adminpassword "mysupersecretpassword"
   #>
   
#Install-Module -Name NetScaler -Force

Param
(
    [Parameter(Mandatory=$true)]$nsip,
    [String]$adminaccount = "***REMOVED***",
    [String]$adminpassword = "***REMOVED***"
)

$User = $adminaccount
$PWord = ConvertTo-SecureString -String $adminpassword -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

Connect-NetScaler -NSIP $nsip -Credential $Credential

$output = Get-NSLicenseExpiration
$output = $output -split "\r?\n"

$output

Disconnect-NetScaler