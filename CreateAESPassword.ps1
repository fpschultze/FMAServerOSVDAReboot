##########################################################################################################################################
#
# Name:				CreateAESPassword
# Author:			Robert Woelfer
# Version: 			1.0
# Last Modified by: Robert Woelfer
# Last Modified on: 12/07/2015 (see history for change details)
#
# History:
# 12/07/15: Version 1.0
#			Version 1.0 created
#
##########################################################################################################################################

<#  
.SYNOPSIS  
    Create AES encrypted password.

.DESCRIPTION
    Creates a AES encrypted password key file within the script folder.
    Access to the AES encrypted password key file must be limited to authorized users, as key and hash file allow decryption of password.
                        
.EXAMPLE
    powershell.exe -ExecutionPolicy RemoteSigned -file <path to script>
#> 

$ScriptRoot = split-path -parent $MyInvocation.MyCommand.Definition
$PwdFile = $ScriptRoot + "\AES.pwd"
$KeyFile = $ScriptRoot + "\AES.key"
$Key = Get-Content $KeyFile
$Pwd = Read-Host "Please enter the password: " -AsSecureString
$Pwd | ConvertFrom-SecureString -key $Key | Out-File $PwdFile

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