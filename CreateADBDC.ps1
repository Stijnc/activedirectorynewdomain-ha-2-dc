﻿#### Remove this if this gets fixed in the extension

try {
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted 
}
catch{
    Write-Verbose 'An exception occurred setting Execution Policy - Trying to Continue -:'
    if ($Error) {
        Write-Verbose ($Error|fl * -Force|Out-String) 
    }
}
   

configuration CreateADBDC 
{ 
   param 
    ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30,
        [String]$DomainNetbiosName=$(Get-NetBIOSName($DomainName))
    ) 
    Import-DscResource -ModuleName xActiveDirectory, xDisk, cDisk
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
   
    Node localhost
    {
        # setting up DNS with default DNS servers for VNet does not work so install DNS and set this VMs DNS tp localhost temporarily
        xWaitforDisk Disk2
        {
             DiskNumber = 2
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
        }
        cDiskNoRestart ADDataDisk
        {
            DiskNumber = 2
            DriveLetter = "F"
            DependsOn = "[xWaitforDisk]Disk2"
        }
        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
            # this is to stop the machine being rebooted during disk initialisation as there is a race condition that can cause disk init to fail
            DependsOn = "[cDiskNoRestart]ADDataDisk"
        } 
        xWaitForADDomain DscForestWait 
        { 
            DomainName = $DomainName 
            DomainUserCredential= $DomainCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec
            DependsOn = "[WindowsFeature]ADDSInstall" 
        } 
        xADDomainController BDC 
        { 
            DomainName = $DomainName 
            DomainAdministratorCredential = $DomainCreds 
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
            DependsOn = "[xWaitForADDomain]DscForestWait" 
        } 

        #### Remove this if this gets fixed in the extension
        Script ResetExecutionPolicy
        {
            SetScript = "Set-ExecutionPolicy -ExecutionPolicy Default"
            TestScript = "((Get-ExecutionPolicy) -eq 'Default')"
            GetScript = "
                `$returnValue = @{
                    Ensure = if ((Get-ExecutionPolicy) -eq 'Default') {'Present'} else {'Absent'}
                }
                `$returnValue
                "
            DependsOn = "[xADDomainController]BDC" 
        }
   }

} 
function Get-NetBIOSName([string]$DomainName)
{ 
    [string]$NetBIOSName
    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        $NetBIOSName=$DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            $NetBIOSName=$DomainName.Substring(0,15)
        }
        else {
            $NetBIOSName=$DomainName
        }
    }
    return $NetBIOSName
}
