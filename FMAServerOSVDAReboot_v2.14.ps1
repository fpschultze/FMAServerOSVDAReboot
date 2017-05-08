##########################################################################################################################################
#
# Name:				FMAServerOSVDAReboot
# Author:			Robert Woelfer
# Version: 			2.14
# Last Modified by: Frank Peter Schultze
# Last Modified on: 08.05.2017
#
# History:
# 12/07/15: Version 2.0
#			Version 2 created based on XenDesktop SDK and invoke-command for DDC
# 12/08/15: Version 2.1
# 			Added support for encrypted credentials / utilize maintenance mode instead of change logon
# 12/09/15: Version 2.2
#			Bugfixing
# 12/10/15: Version 2.3
#			Code cosmetic
# 12/14/15: Version 2.4
#			Added support for non-power-managed machines
# 01/05/16: Version 2.5
#			Bugfixing
# 01/12/16: Version 2.6
#			Added support to delaying first message sent to users
# 01/14/16: Version 2.7
#			Extended random value to 10 - 900 seconds (max. 15 minutes)
# 02/15/16: Version 2.8
#			Insert delay between enable maintenance mode and check maintenanc mode
# 02/22/16: Version 2.9
#			Append logs instead of creating a new log file each time script runs.
# 02/29/16: Version 2.10
#			Added option to restart immediately if no sessions found on the server (default is wait till end of reboot sequence).
# 05/24/16: Version 2.11
#			Detailed logging information.
# 05/31/16: Version 2.12
#			Added initial delay for controller connection.
# 09/23/16: Version 2.13
#			Code cosmnetic.
# 08.05.17: Version 2.14
#           Get credential from key and pwd xml files
##########################################################################################################################################

<#  
.SYNOPSIS  
    Disables new user sessions, retrieves all user sessions from local computer, sends user messages, logs off users and reboots server

.DESCRIPTION
    Disables new user sessions, retrieves all user sessions from local computer, sends user messages, logs off users and reboots server
    
    Note:
    Requires connection to the Delivery Controllers of the XenDesktop site.
    Credentials to acccess XenDesktop site and perform session and machine actions are required to be stored encrypted in the root directory of the script: 
		Set service account within the script according to the environment within the credentials section.
        Password file = AES.pwd / Key file = AES.key
    If other location is required change the path under the credential section in this script.
    Ensure access to the key and password files are restricted as both files allow decryption of the password.
    Scripts to create key and password files are provided together with the reboot script: 
        CreateAESKey.ps1 / CreateAESPassword.ps1
   
.PARAMETER RebootCycle
    Disable logon prior to the reboot sequence.
    Default cycle is 1 hour (3600 seconds).
    Only relevant if ForceLogoff = 1

.PARAMETER FirstMsgDelay
    Delay first user message in seconds.
    Default delay is 0 minutes.
              
.PARAMETER MsgDelay
    Delay between user messages in seconds.
    Default delay is 10 minutes (600 seconds).
    
.PARAMETER LogoffDelay 
    Delay between last user messages and forced user logoff.
    Default delay is 5 minutes (300 seconds).
    Only relevant if ForceLogoff = 1
  
.PARAMETER RebootDelay
    Delay between forced user logoff and server reboot.
    Default delay is 5 minutes (300 seconds).

.PARAMETER ForceLogoff
	Choose wether session logoff is enforced (1) or not (0).
	Default is no enforcement (0).

.PARAMETER ImmediateRestart
    Choose whether restart will occure immediately if no sessions are found on server (1) or not (0).
    Default is wait till end of reboot sequence (0).
                        
.EXAMPLE
    no logoff enforcement: 
        powershell.exe -ExecutionPolicy RemoteSigned ñFile <path to script> -FirstMsgDelay 600 -MsgDelay 600 -RebootDelay 300 -ForceLogoff 0 -ImmediateRestart 0
    logoff enforcement: 
        powershell.exe -ExecutionPolicy RemoteSigned -file <path to script> -RebootCycle 3600 -FirstMsgDelay 600 -MsgDelay 600 -LogoffDelay 300 -RebootDelay 300 -ForceLogoff 1 -ImmediateRestart 0
	
    Disables new user sessions.
    Query all current user sessions on 'localhost' for 1 hour every 10 minutes and send messages to current user sessions to inform users about pending reboot.
    First message is send after 10 minutes.
    Sends final message after 1 hour is reached to current user sessions and logs of users 5 minutes later.
    Another 5 minutes later the server is restarted.

.NOTES
    Run script from task scheduler.
    Example: powershell.exe -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File <path to script> -RebootCyle 3600 -MsgDelay 600 -LogoffDelay 300 -RebootDelay 300 -ForceLogoff 0
    
	Create scheduled task by utilizing Group Policy Preferences.
    For staggered reboots split servers into OUs or Active Directory Security Groups.
    Create different scheduled tasks filtered based on OUs or Active Directory Security Groups to reflect the required reboot schedule.
#> 

#Read the parameters passed from command line
Param(
    #Delay in seconds between first user message and server reboot (default 1 hour).
    [int]$RebootCycle = 3600,
    #Delay first user message in seconds (default 0 minutes).
    [int]$FirstMsgDelay = 0,
    #Delay between user messages in seconds (default 10 minutes).
    [int]$MsgDelay = 600,
    #Delay in seconds between last user message and forced logoff of still existing sessions (default 5 minutes).
    [int]$LogoffDelay = 300,
    #Delay in seconds between forced user logoff and server reboot (default 5 minutes).
    [int]$RebootDelay = 300,
    #Session logoff enforcement (default no enforcement).
    [int]$ForceLogoff = 0,
    #Immediate restart (default wait till end of reboot sequence)
    [int]$ImmediateRestart = 0
    )
	
#Set script parameter
$LogDir = "D:\Logs\Reboot"
$LogFile = $LogDir + "\Reboot.log"
#Generate random value to spread load on controller.
$InitDelay = (Get-Random -Maximum 60 -Minimum 5)
#Generate random value to ensure servers are not rebooted at the same time.
$StartDelay = (Get-Random -Maximum 900 -Minimum 10)
#LogoffDelay in minutes for user message text.
$LogoffDelayMsg = [math]::round($LogoffDelay/10)
#Number of user messages till final message is send and reboot initiated. 
#Calculated based on reboot delay and message delay (default 6 messages every 10 minutes).
$Iterations = [math]::round(($RebootCycle - $FirstMsgDelay)/$MsgDelay)
#User message content.
#Message title
$MsgT = "Server Reboot Schedule"
#Message body random message
$MsgB1 = "Due to maintenance the Citrix server needs to be rebooted. Please save all your work and log off from your Citrix session. You can reconnect to your applications and desktops immediately."
#Message body final message prior to logoff
$MsgB2 = "Due to maintenance the Citrix server needs to be rebooted. Please save all your work and log off from your Citrix session. You can reconnect to your applications and desktops immediately." + "`n" + "`n" + "NOTE: You will get logged off from your Citrix session in $LogoffDelayMsg minutes automatically."

#Get script parameter
$sCompName = $env:COMPUTERNAME
$sDNSDomName = (Get-WmiObject Win32_ComputerSystem).Domain
$aDNSDomName = $sDNSDomName.split(".")
$sCompDomName = $aDNSDomName[0]
$sMachineName = $sCompDomName + "\" + $sCompName
$sDDC = (Get-ItemProperty Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Citrix\VirtualDesktopAgent\Policy -Name RegisteredDdcFqdn).RegisteredDdcFqdn
$ScriptRoot = split-path -parent $MyInvocation.MyCommand.Definition

<#Credentials
$SvcAcc = "ctx-xa-reboot-svc"
$sSvcDomName = $aDNSDomName[1]
$User = $sSvcDomName + "\" + $SvcAcc
$PwdFile = $ScriptRoot + "\AES.pwd"
$KeyFile = $ScriptRoot + "\AES.key"
$key = Get-Content $KeyFile
$SecCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, (Get-Content $PwdFile | ConvertTo-SecureString -Key $key)
#>

#Credentials (modified by FPS)
$SvcAcc = "ctx-xa-reboot-svc"
$sSvcDomName = $env:USERDOMAIN # $aDNSDomName[1]
$User = '{0}\{1}' -f $sSvcDomName, $SvcAcc
$PwdFile = '{0}\AES.pwd.xml' -f $ScriptRoot
$KeyFile = '{0}\AES.key.xml' -f $ScriptRoot
$Key = Import-Clixml -Path $KeyFile
$Pwd = Import-Clixml -Path $PwdFile
$SecCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, ($Pwd | ConvertTo-SecureString -Key $key)

#Test log directory and create if not existing
if(!(Test-Path -Path $LogDir )){
	New-Item -ItemType directory -Path $LogDir
}

#Main function for Server VDA reboot
function fServerVDAReboot ($sMachineName, $sDDC, $SecCred, $LogFile, $StartDelay, $FirstMsgDelay, $MsgDelay, $LogoffDelay, $RebootDelay, $Iterations, $MsgT, $MsgB1, $MsgB2, $ForceLogoff, $ImmediateRestart){
	Write-Output $("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++") | out-file $LogFile -Append
    Write-Output $("") | out-file $LogFile -Append
    Write-Output $("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++") | out-file $LogFile -Append
    Write-Output $("Server VDA Reboot Schedule") | out-file $LogFile -Append
	Write-Output $("----------------------------------------------------------------------------------") | out-file $LogFile -Append
	Write-Output $("OS VERSION: " + "`t" + "`t" + [Environment]::OSVersion), $("MACHINE NAME: " + "`t" + "`t" + $sMachineName), $("START DELAY: " + "`t" + "`t" + $StartDelay), $("REBOOT CYCLE: " + "`t" + "`t" + $RebootCycle), $("FIRST MESSAGE DELAY: " + "`t" + $FirstMsgDelay), $("MESSAGE DELAY: " + "`t" + "`t" + $MsgDelay), $("LOGOFF DELAY: " + "`t" + "`t" + $LogoffDelay), $("REBOOT DELAY: " + "`t" + "`t" + $RebootDelay), $("ITERATIONS:  " + "`t" + "`t" + $Iterations), $("LOGOFF FORCED: " + "`t" + "`t" + $ForceLogoff), $("XENDESKTOP CONTROLLER: " + "`t" + $sDDC) | out-file $LogFile -Append
	Write-Output $("SCRIPT ROOT: " + "`t" + "`t" + $ScriptRoot) | out-file $LogFile -Append
    Write-Output $("----------------------------------------------------------------------------------") | out-file $LogFile -Append
	Write-Output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": S-T-A-R-T") | out-file $LogFile -Append
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $InitDelay + " seconds before initial Controller connection") | out-file $LogFile -Append
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = INITIAL DELAY:" + $InitDelay) | out-file $LogFile -Append
    Start-Sleep -s $InitDelay
    #Create Powershell session with DDC
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Create remote PoSH session: " + $sDDC) | out-file $LogFile -Append
    $sPSSession = New-PSSession -ComputerName $sDDC -Credential $SecCred
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + $sPSSession.Name + "__ComputerName:" + $sPSSession.ComputerName + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
  	#Load Citrix snapins
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Loading Citrix Snapins") | out-file $LogFile -Append 
    $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
    if ($snapins -eq $null){
        invoke-command -Session $sPSSession { Get-PSSnapin -Registered "Citrix.Broker.Admin.V2" | Add-PSSnapin }
    }
    $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Snapins:" + $snapins) | out-file $LogFile -Append
    #Disable logon but allow reconnect to existing sessions.
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Drain sessions - enable maintenance mode") | out-file $LogFile -Append
    invoke-command -Session $sPSSession { param ($sMachineName) (Set-BrokerMachineMaintenanceMode $sMachineName -MaintenanceMode $True) } -ArgumentList $sMachineName
    Start-Sleep -s 10
    $sMMode = invoke-command -Session $sPSSession { param ($sMachineName) ((Get-BrokerMachine $sMachineName).InMaintenanceMode) } -ArgumentList $sMachineName
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Maintenance Mode:" + $sMMode) | out-file $LogFile -Append
    if ($sMMode -ne "True"){
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": ERROR: Maintenance Mode not enabled. Terminating reboot sequence.") | out-file $LogFile -Append
        #End PoSH session with DDC
        Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
        Remove-PSSession $sPSSession
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": E-N-D") | out-file $LogFile -Append	
        exit
    }
    #End PoSH session with DDC
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
    Remove-PSSession $sPSSession
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
	#Random delay to prevent restart of servers at same time
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $StartDelay + " seconds before starting reboot sequence") | out-file $LogFile -Append
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = START DELAY:" + $StartDelay) | out-file $LogFile -Append
	Start-Sleep -s $StartDelay
	#Run reboot sequence depending on logoff behavior
	if ($ForceLogoff -eq 0){
		#Send messages to users logged on
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Start sending messages until last user logged off") | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $FirstMsgDelay + " seconds before first user message") | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = FIRST MESSAGE DELAY:" + $FirstMsgDelay) | out-file $LogFile -Append
        Start-Sleep -s $FirstMsgDelay
		fSendUserMessage $sMachineName $sDDC $SecCred $LogFile $Iterations $MsgT $MsgB1 $MsgB2 $MsgDelay $ForceLogoff $ImmediateRestart
		#Reboot Server
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $RebootDelay + " seconds until server reboot") | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = REBOOT DELAY:" + $RebootDelay) | out-file $LogFile -Append
		Start-Sleep -s $RebootDelay
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Initiate Reboot") | out-file $LogFile -Append
		fRebootVDA $sMachineName $sDDC $SecCred $LogFile
	}
	if ($ForceLogoff -eq 1){
		#Send messages to users logged on
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Start sending messages - Iterations: " + $Iterations + " - then logging off remaining users") | out-file $LogFile -Append
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $FirstMsgDelay + " seconds before first user message") | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = FIRST MESSAGE DELAY:" + $FirstMsgDelay) | out-file $LogFile -Append
        Start-Sleep -s $FirstMsgDelay
		fSendUserMessage $sMachineName $sDDC $SecCred $LogFile $Iterations $MsgT $MsgB1 $MsgB2 $MsgDelay $ForceLogoff $ImmediateRestart
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $LogoffDelay + " seconds until logging off remaining users") | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = LOGOFF DELAY:" + $LogoffDelay) | out-file $LogFile -Append
		Start-Sleep -s $LogoffDelay
		#Force logoff of users still logged on
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Logging off remaining users") | out-file $LogFile -Append
		fUserLogoffForce $sMachineName $sDDC $SecCred $LogFile
		#Reboot Server
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $RebootDelay + " seconds until server reboot") | out-file $LogFile -Append
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = REBOOT DELAY:" + $RebootDelay) | out-file $LogFile -Append
		Start-Sleep -s $RebootDelay
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Initiate Reboot") | out-file $LogFile -Append
		fRebootVDA $sMachineName $sDDC $SecCred $LogFile
	}
}

#Send messages to active and disconnected sessions
function fSendUserMessage ($sMachineName, $sDDC, $SecCred, $LogFile, $Iterations, $MsgT, $MsgB1, $MsgB2, $MsgDelay, $ForceLogoff, $ImmediateRestart){
	#Counter for sending user messages
	if ($ForceLogoff -eq 0){
        $Count = 0
		do {
			Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Sending messages to all active and disconnected sessions") | out-file $LogFile -Append
			$SesCnt = 0
            #Create Powershell session with DDC
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Create remote PoSH session: " + $sDDC) | out-file $LogFile -Append
            $sPSSession = New-PSSession -ComputerName $sDDC -Credential $SecCred
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + $sPSSession.Name + "__ComputerName:" + $sPSSession.ComputerName + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
            #Load Citrix snapins
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Loading Citrix Snapins") | out-file $LogFile -Append  
            $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
            if ($snapins -eq $null){
                invoke-command -Session $sPSSession { Get-PSSnapin -Registered "Citrix.Broker.Admin.V2" | Add-PSSnapin }
            }
            $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Snapins:" + $snapins) | out-file $LogFile -Append
            #Get sessions
            $oSessions = invoke-command -session $sPSSession { param ($sMachineName) (Get-BrokerSession -MachineName $sMachineName).Uid } -ArgumentList $sMachineName
			#Send user message
			if ($oSessions -ne $null) {
				foreach ($ID in $oSessions){
					invoke-command -session $sPSSession {param ($ID,$MsgT,$MsgB1) (Send-BrokerSessionMessage $ID -MessageStyle Information -Title $MsgT -Text $MsgB1) } -ArgumentList $ID,$MsgT,$MsgB1
					$SesCnt++
				}
			}
            $Count++
			Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Session Count = " + $SesCnt) | out-file $LogFile -Append
            #End PoSH session with DDC
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
            Remove-PSSession $sPSSession
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
            Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $MsgDelay + " seconds until sending next message") | out-file $LogFile -Append
            Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = MESSAGE DELAY:" + $MsgDelay) | out-file $LogFile -Append
            Start-Sleep -s $MsgDelay
            if (($ImmediateRestart -eq 1) -and ($SesCnt -eq 0)){
                    $Count = $Iterations
            }
		}
		while (($SesCnt -gt 0) -or ($Count -lt $Iterations))
	}
	if ($ForceLogoff -eq 1){
        $Count = 0
		do {
            $SesCnt = 0
            #Create Powershell session with DDC
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Create remote PoSH session: " + $sDDC) | out-file $LogFile -Append
            $sPSSession = New-PSSession -ComputerName $sDDC -Credential $SecCred
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + $sPSSession.Name + "__ComputerName:" + $sPSSession.ComputerName + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
            #Load Citrix snapins
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Loading Citrix Snapins") | out-file $LogFile -Append 
            $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
            if ($snapins -eq $null){
                invoke-command -Session $sPSSession { Get-PSSnapin -Registered "Citrix.Broker.Admin.V2" | Add-PSSnapin }
            }
            $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Snapins:" + $snapins) | out-file $LogFile -Append
            #Get sessions
            $oSessions = invoke-command -session $sPSSession { param ($sMachineName) (Get-BrokerSession -MachineName $sMachineName).Uid } -ArgumentList $sMachineName
			#Send user message
			Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Sending messages to all active and disconnected sessions") | out-file $LogFile -Append
			if ($oSessions -ne $null){
				foreach ($ID in $oSessions){
					invoke-command -session $sPSSession {param ($ID,$MsgT,$MsgB1) (Send-BrokerSessionMessage $ID -MessageStyle Information -Title $MsgT -Text $MsgB1) } -ArgumentList $ID,$MsgT,$MsgB1
					$SesCnt++
				}
			}
			$Count++
			Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Session Count = " + $SesCnt) | out-file $LogFile -Append
			#End PoSH session with DDC
			Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
            Remove-PSSession $sPSSession
            Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append      
            Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Wait " + $MsgDelay + " seconds until sending next message") | out-file $LogFile -Append
            Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = MESSAGE DELAY:" + $MsgDelay) | out-file $LogFile -Append
            Start-Sleep -s $MsgDelay
            if (($ImmediateRestart -eq 1) -and ($SesCnt -eq 0)){
                    $Count = $Iterations
            }			
		}
		while ($Count -lt $Iterations)
		#Send final message to users still logged on, start immediately and send only one message
        Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Sending final message prior to restart") | out-file $LogFile -Append
		$SesCnt = 0
		#Create Powershell session with DDC
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Create remote PoSH session: " + $sDDC) | out-file $LogFile -Append
        $sPSSession = New-PSSession -ComputerName $sDDC -Credential $SecCred
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + $sPSSession.Name + "__ComputerName:" + $sPSSession.ComputerName + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
        #Load Citrix snapins
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Loading Citrix Snapins") | out-file $LogFile -Append 
        $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
        if ($snapins -eq $null){
			invoke-command -Session $sPSSession { Get-PSSnapin -Registered "Citrix.Broker.Admin.V2" | Add-PSSnapin }
        }
        $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Snapins:" + $snapins) | out-file $LogFile -Append
		#Get sessions
        $oSessions = invoke-command -session $sPSSession { param ($sMachineName) (Get-BrokerSession -MachineName $sMachineName).Uid } -ArgumentList $sMachineName
		if ($oSessions -ne $null){
			foreach ($ID in $oSessions){
				invoke-command -session $sPSSession {param ($ID,$MsgT,$MsgB2) (Send-BrokerSessionMessage $ID -MessageStyle Information -Title $MsgT -Text $MsgB2) } -ArgumentList $ID,$MsgT,$MsgB2
				$SesCnt++
			}
		}		
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Session Count = " + $SesCnt) | out-file $LogFile -Append
		#End PoSH session with DDC
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
        Remove-PSSession $sPSSession
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
	}
}

#Force logoff of active and disconnected sessions
function fUserLogoffForce ($sMachineName, $sDDC, $SecCred, $LogFile){
	$SesCnt = 0
    #Create Powershell session with DDC
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Create remote PoSH session: " + $sDDC) | out-file $LogFile -Append
    $sPSSession = New-PSSession -ComputerName $sDDC -Credential $SecCred
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + $sPSSession.Name + "__ComputerName:" + $sPSSession.ComputerName + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
    #Load Citrix snapins
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Loading Citrix Snapins") | out-file $LogFile -Append 
    $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
    if ($snapins -eq $null){
        invoke-command -Session $sPSSession { Get-PSSnapin -Registered "Citrix.Broker.Admin.V2" | Add-PSSnapin }
    }
    $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Snapins:" + $snapins) | out-file $LogFile -Append
    #Get sessions
    $oSessions = invoke-command -session $sPSSession { param ($sMachineName) (Get-BrokerSession -MachineName $sMachineName).Uid } -ArgumentList $sMachineName
	#Log off remaining users
	Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Logging off remaining sessions") | out-file $LogFile -Append
	if ($oSessions -ne $null){
		foreach ($ID in $oSessions){
			invoke-command -session $sPSSession {param ($ID) (Stop-BrokerSession $ID) } -ArgumentList $ID
			$SesCnt++
		}
	}
	Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Session Count = " + $SesCnt) | out-file $LogFile -Append
    #End PoSH session with DDC
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
    Remove-PSSession $sPSSession
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
}

#Reboot VDA
function fRebootVDA ($sMachineName, $sDDC, $SecCred, $LogFile){
    #Create Powershell session with DDC
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Create remote PoSH session: " + $sDDC) | out-file $LogFile -Append
    $sPSSession = New-PSSession -ComputerName $sDDC -Credential $SecCred
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + $sPSSession.Name + "__ComputerName:" + $sPSSession.ComputerName + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
    #Load Citrix snapins
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Loading Citrix Snapins") | out-file $LogFile -Append 
    $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
    if ($snapins -eq $null){
        invoke-command -Session $sPSSession { Get-PSSnapin -Registered "Citrix.Broker.Admin.V2" | Add-PSSnapin }
    }
    $snapins = invoke-command -Session $sPSSession { (Get-PSSnapin | where { $_.Name -like "Citrix.Broker.Admin.V2" }) }
    Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Snapins:" + $snapins) | out-file $LogFile -Append
	#Disable maintenance mode
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Disable maintenance mode for machine $sMachineName") | out-file $LogFile -Append
	$sMMode = invoke-command -Session $sPSSession { param ($sMachineName) (Set-BrokerMachineMaintenanceMode $sMachineName -MaintenanceMode $False) } -ArgumentList $sMachineName
    Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = Maintenance Mode:" + $sMMode) | out-file $LogFile -Append
	#Restart VDA - check if machine is power managed
	$sHypCon = invoke-command -Session $sPSSession { param ($sMachineName) ((Get-BrokerMachine $sMachineName).PowerState) } -ArgumentList $sMachineName
	if ((($sHypCon).Value) -eq "Unmanaged"){
		#End PoSH session with DDC
		Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Machine $sMachineName is not power managed") | out-file $LogFile -Append
		Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
		Remove-PSSession $sPSSession
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
		Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Restarting machine $sMachineName") | out-file $LogFile -Append
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": E-N-D") | out-file $LogFile -Append
		Restart-Computer -Force -ErrorAction SilentlyContinue		
	}
	else{
		Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Machine $sMachineName is power managed") | out-file $LogFile -Append
		Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Sending power action to DDC for machine $sMachineName") | out-file $LogFile -Append
		invoke-command -session $sPSSession { param ($sMachineName) (New-BrokerHostingPowerAction -MachineName $sMachineName -Action Restart) } -ArgumentList $sMachineName
        $sPwAct = invoke-command -session $sPSSession { param ($sMachineName) ((Get-BrokerHostingPowerAction -MachineName $sMachineName).State) } -ArgumentList $sMachineName
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = BrokerHostingPowerActionState:" + $sPwAct) | out-file $LogFile -Append
		#End PoSH session with DDC
		Write-output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": Remove remote PoSH session: " + $sDDC) | out-file $LogFile -Append
		Remove-PSSession $sPSSession
        Write-output  $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": DEBUG INFO = ID:" + $sPSSession.Id + "__Name:" + "__ComputerName:" + $sPSSession.ComputerName + $sPSSession.Name + "__State:" + $sPSSession.State + "__Availability:" + $sPSSession.Availability) | out-file $LogFile -Append
		Write-Output $([DateTime]::Now.toString("yyyy-MM-dd_HHmmss") + ": E-N-D") | out-file $LogFile -Append		
    }
}

#Call main function to perform reboot
fServerVDAReboot $sMachineName $sDDC $SecCred $LogFile $StartDelay $FirstMsgDelay $MsgDelay $LogoffDelay $RebootDelay $Iterations $MsgT $MsgB1 $MsgB2 $ForceLogoff $ImmediateRestart

##########################################################################################################################################
# 							
# *******************************************************   LEGAL DISCLAIMER   ***********************************************************
#
# This software / sample code is provided to you "AS IS"ù with no representations, warranties or conditions of any kind. You may use, 
# modify and distribute it at your own risk. CITRIX DISCLAIMS ALL WARRANTIES WHATSOEVER, EXPRESS, IMPLIED, WRITTEN, ORAL OR STATUTORY, 
# INCLUDING WITHOUT LIMITATION WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NONINFRINGEMENT. Without 
# limiting the generality of the foregoing, you acknowledge and agree that (a) the software / sample code may exhibit errors, design 
# flaws or other problems, possibly resulting in loss of data or damage to property; (b) it may not be possible to make the software / 
# sample code fully functional; and (c) Citrix may, without notice or liability to you, cease to make available the current version and / 
# or any future versions of the software / sample code. In no event should the software / code be used to support of ultra-hazardous 
# activities, including but not limited to life support or blasting activities. NEITHER CITRIX NOR ITS AFFILIATES OR AGENTS WILL BE 
# LIABLE, UNDER BREACH OF CONTRACT OR ANY OTHER THEORY OF LIABILITY, FOR ANY DAMAGES WHATSOEVER ARISING FROM USE OF THE SOFTWARE / SAMPLE 
# CODE, INCLUDING WITHOUT LIMITATION DIRECT, SPECIAL, INCIDENTAL, PUNITIVE, CONSEQUENTIAL OR OTHER DAMAGES, EVEN IF ADVISED OF THE 
# POSSIBILITY OF SUCH DAMAGES. Although the copyright in the software / code belongs to Citrix, any distribution of the code should 
# include only your own standard copyright attribution, and not that of Citrix. You agree to indemnify and defend Citrix against any and 
# all claims arising from your use, modification or distribution of the code.
#
##########################################################################################################################################