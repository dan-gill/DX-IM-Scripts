<#
.SYNOPSIS
   Grabs Netscaler license information via PS
.DESCRIPTION
   Grabs Netscaler license information via PS.
.NOTES
    File Name  : get-nslicexp.ps1
    Author     : Dan Gill - dgill@gocloudwave.com
.INPUTS
   NetScaler IP, Admin user, Admin password as Secure String
.OUTPUTS
   Outputs license expiration
.PARAMETER nsip
   DNS Name or IP of the Netscaler that needs to be configured. (MANDATORY)
.PARAMETER adminaccount
   Netscaler admin account (MANDATORY)
.PARAMETER adminpassword
   Password for the Netscaler admin account (MANDATORY)
.EXAMPLE
   ./get-NSlicexp -nsip 10.1.1.2 -adminaccount nsadmin -adminpassword (ConvertTo-SecureString "mysupersecretpassword" -AsPlainText -Force)
#>

# Install NetScaler PowerShell module if not installed
if (!(Get-Module -ListAvailable -Name NetScaler)) {
    Install-Module -Name NetScaler -Scope CurrentUser
}

Param
(
   [Parameter(Mandatory=$true,
              ValueFromPipelineByPropertyName=$true,
              Position=0)]
   [string]$nsip,
   [Parameter(Mandatory=$true,
              ValueFromPipelineByPropertyName=$true,
              Position=1)]
   [ValidateNotNullOrEmpty()]
   [String]$adminaccount,
   [Parameter(Mandatory=$true,
              ValueFromPipelineByPropertyName=$true,
              Position=2)]
   [ValidateNotNullOrEmpty()]
   [Security.SecureString]$adminpassword = $(Throw 'Password required.')
)

$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $adminaccount, $adminpassword

Connect-NetScaler -NSIP $nsip -Credential $Credential

$output = Get-NSLicenseExpiration
$output = $output -split '\r?\n'

$output

Disconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScalerDisconnect-NetScaler
Disconnect-NetScaler