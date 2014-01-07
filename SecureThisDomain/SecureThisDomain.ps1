# PreRequisites
#	1. User running the script must be a Domain Admin
#	2. ActiveDirectory and GroupPolicy modules must be available from RSAT. http://www.microsoft.com/en-us/download/details.aspx?id=7887
#	3. Machine running the script must be a domain member.


############### GLOBAL VARS ###############

#Current User Name
$struser = $env:USERNAME

#Current Domain Name
$strdomain = $env:USERDOMAIN

# Fully qualified host name
$hostname = $null

#Current Domain Object
$domain = $null

#Current User Object
$currentuser = $null

# XML based list of domain GPOs
[xml]$gpos = $null

# XML based RSOP data for both user & computer
[xml]$rsop = $null

$windowoffset = [Console]::WindowWidth / 2

############### SUPPORTING FUNCTIONS ###############

# Load a module if it's available
Function Get-MyModule { 
	Param([string]$name) 
	if(-not(Get-Module -name $name)) 
	{ 
		if(Get-Module -ListAvailable | 
		Where-Object { $_.name -eq $name }) 
		{ 
			Import-Module -Name $name 
			$true 
		}  
		else { $false } 
		}	 
	else { $true }
}

# Write messages to console
Function Write-Message {
	Param(	[string] $message,
			[string] $type)
	switch ($type) {
		"error" {Write-Host "[!] - $message" -ForegroundColor Red}
		"warning" {Write-Host "[!] - $message" -ForegroundColor Yellow}
		"debug" {$Host.UI.WriteDebugLine($message)}
		"success" {Write-Host "[+] - $message" -ForegroundColor Green}
		"prereq" {Write-Host "[+] - PREREQ CHECK: $message" -ForegroundColor Cyan}
		default {Write-Host $message}
	}
}

# Perform Prereq checks and load modules
Function DoPreReqs {
	# Load AD Module
	if ((Get-MyModule -name "ActiveDirectory") -eq $false) {
		Write-Message "ActiveDirectory module not available. Please load the Remote Server Administration Tools from Microsoft." "error"
		exit
	} else {Write-Message "ActiveDirectory module successfully loaded." "prereq"}

	#Load GPO Module
	if ((Get-MyModule -name "GroupPolicy") -eq $false) {
		Write-Message "GroupPolicy module not available. Please load the Remote Server Administration Tools from Microsoft." "error"
		exit
	} else {Write-Message "GroupPolicy module successfully loaded." "prereq"}

	# Check if machine is on a domain
	if ([string]::IsNullOrEmpty($env:USERDOMAIN)) {
		Write-Message "Bad news. Looks like this machine is not a member of a domain. Please run from a member server or workstation, or a domain controller" "error"
		exit
	} else { Write-Message "Machine is member of $strdomain domain." "prereq" }

	$global:domain = Get-ADDomain $strdomain
	$global:currentuser = Get-ADUser $struser -Properties memberOf
	$global:hostname = [System.Net.Dns]::GetHostByName(($env:computerName)) | select -ExpandProperty HostName

	#Domain Admin Check
	if ($global:currentuser.MemberOf | Select-String "CN=Domain Admins") {
		Write-Message "Current user is a Domain Admin." "prereq"
	} else { 
		Write-Message "Bad news. The user running this script must be a Domain Admin. Exiting.." "error"
		exit
	}
	
	#Domain Controller Check
	if ($global:domain.ReplicaDirectoryServers.Contains($global:hostname)) {
		Write-Message "SecureThisDomain is running on a DC" "prereq"
	} else {
		Write-Message "SecureThisDomain must be running on a DC." "error"
		exit
	}
	
	# Export all gpo settings to xml
	try {
		$gpopath = "$env:TEMP/gpodata.xml"
		Get-GPOReport -All -Path $gpopath -ReportType Xml
		[xml]$global:gpos = gc $gpopath
		Write-Message "Successfully exported GPOs from domain $strdomain" "prereq"
	} catch [Exception] {
		$err = $_.Exception.Message
		Write-Message "Failed to export GPOs from domain $strdomain. Error: $err. Exiting..." "error"
		exit
	}
	
	#Export RSOP data to xml
	try {
		$rsoppath = "$env:TEMP/rsopdata.xml"
		Get-GPResultantSetOfPolicy -Path $rsoppath -ReportType Xml | Out-Null
		[xml]$global:rsop = gc $rsoppath
		Write-Message "Successfully exported & loaded RSOP data." "prereq"
	} catch [Exception] {
		$err = $_.Exception.Message
		Write-Message "Failed to export RSOP data for current user/machine. Error: $err. Exiting..." "error"
		exit
	}
}

Function Write-Centered {
	Param(	[string] $message,
			[string] $color = "black",
			[bool]	$ismenuitem = $false)
	if ($ismenuitem) {
		[int]$offsetvalue = ([Console]::WindowWidth / 2) * .65
		Write-Host ("{0,$offsetvalue}{1}" -f " ",$message) -ForegroundColor $color
	}
	else {
		[int]$offsetvalue = ([Console]::WindowWidth / 2) + ($message.Length / 2)
		Write-Host ("{0,$offsetvalue}" -f $message) -ForegroundColor $color
	}
}

Function Menu {
	#CLS
	Write-Host "`n`n"
	Write-Centered "############ SecureThisDomain ############`n" "Magenta"
	Write-Centered "SecureThisDomain helps you secure your Active Directory domain" "Yellow"
	Write-Centered "against the most common hacking techniques`n`n" "Yellow"
	Write-Centered "Main Menu`n" "Cyan"
	Write-Centered "1. EVAL - Domain Admins" "Cyan" $true
	Write-Centered "2. EVAL - Domain Controllers" "Cyan" $true
	Write-Centered "3. Secure Domain Admins" "Cyan" $true
	Write-Centered "4. Secure Domain Controllers" "Cyan" $true
	Write-Centered "5. Death Blossum (Lock it all down now!)" "Cyan" $true
	Write-Centered "6. Show Help" "Cyan" $true
	Write-Centered "7. Quit" "Cyan" $true
	Write-Host "`n`n"
	$optionstring = [string]::Format("{0,$windowoffset}", "Please select an option")
	return Read-Host $optionstring
}

Function Write-Help {
	Write-Message	"

	***** SECURETHISDOMAIN *****

	SecureThisDomain.ps1 uses Group Policy to create a tightly controlled environment 
	for your Domain Controllers (DC) and your Domain Admins (DA). Both DCs and DAs 
	are high value targets for pentesters and hackers alike and, if compromised, basically 
	represent ownage of your domain/network. This script is designed to seriously 
	slow them down, allowing you more time to detect and mitigate internal threats against your AD environment.

	* It will create a GPO called 'Core AD Security Policy' and add the following 
	settings to it (with your permission):
	
		1. Disable null sessions on your DCs.
		2. Ensure that DAs can only login to DCs.
		3. Tighten down your DA password policy.
			a. Minimum 10 characters (Default AD is 7).
			b. Complexity enforced
			c. Indefinite lockout after 5 bad attempts (Default AD is Never Lockout. Lame.)
		4. Remove Credential Caching on your DCs.
		5. Enforce 2 way SMB signing on your DCs.
		6. Ensure object level AD auditing is enabled.
		
	"
}

Function EvalDAs {
	Write-Host "`n`n"
	$sec = $global:rsop.Rsop.ComputerResults.ExtensionData | ?{$_.Name."#text" -eq "Security"} | select Extension
	$minpwdage = $sec.Extension.Account | ?{$_.Name -eq "MinimumPasswordAge"} | select -ExpandProperty SettingNumber
	$lockoutcount = $sec.Extension.Account | ?{$_.Name -eq "LockoutBadCount"} | select -ExpandProperty SettingNumber
	$minpwdlength = $sec.Extension.Account | ?{$_.Name -eq "MinimumPasswordLength"} | select -ExpandProperty SettingNumber
	$pwdcomplexity = $sec.Extension.Account | ?{$_.Name -eq "PasswordComplexity"} | select -ExpandProperty SettingBoolean
	$pwdhistory = $sec.Extension.Account | ?{$_.Name -eq "PasswordHistorySize"} | select -ExpandProperty SettingNumber
	
	$das = Get-ADGroupMember "Domain Admins" | Get-ADUser -Properties LogonWorkstations
	
	Write-Debug "Minimum Password Age: $minpwdage"
	Write-Debug "LockoutCount: $lockoutcount"
	Write-Debug "Minimum Password Length: $minpwdlength"
	Write-Debug "Complexity Enabled: $pwdcomplexity"
	Write-Debug "Password History Count: $pwdhistory"
	
	#Count DAs
	if ($das.Count -lt 2) { Write-Message "You have less than 2 DAs. What will the company do if something bad happens to you? Each domain needs at least 2 DAs (but not many more)." "warning" }
	elseif ($das.Count -gt 10) {Write-Message "You have more than 10 DAs. This most likely is due to insufficient delegated permissions. Consider delegating perms to some of your DAs, then removing their rights." "warning" }
	else {Write-Message "DA count looks good. Not too many, not too few." "success"}
	
	#Password History Check
	if ($pwdhistory -lt $lockoutcount) {Write-Message "The password history count ($pwdhistory) is less than the lockout threshold ($lockoutcount). This means an attacker has a greater chance of guessing your password without you knowing about it. Your lockout threshold should be higher than your minimum password age." "warning"}
	elseif ($pwdhistory -lt 10) {Write-Message "Your password history ($pwdhistory passwords remembered) is less than 10. This makes it easier for users to rotate though fewer passwords and is a greater security risk. Up this number to be on the safe side." "warning"}
	else {Write-Message "Your password history count ($pwdhistory passwords remembered) looks good for DAs." "success" }
	
	#Lockout Count Check
	if ($lockoutcount -eq 0) {Write-Message "The Lockout Count is set to 0. This means that accounts can never be locked out. no no NO!" "error"}
	elseif ($lockoutcount -gt 10) {Write-Message "The Lockout Count is set to $lockoutcount. Really? Tighten this up to somewhere between 3-8 to be on the safe side" "warning"}
	else {Write-Message "The Lockout Count is set to $lockoutcount. Looks good." "success" }
	
	#Password Complexity Check
	if ($pwdcomplexity -eq $true) {Write-Message "Password complexity is enabled." "success"}
	else {Write-Message "Password complexity is not enabled. Consider enabling it. This makes passwords harder to attack." "warning"}
	
	#Logon Workstation Check
	$baddalogon = @()
	$unuseddas = @()
	$dcsnetbios = $global:domain.ReplicaDirectoryServers | %{$_.Trim($global:domain.DNSRoot)}
	foreach ($da in $das) {
		if (!$da.LogonWorkstations) {$baddalogon += $da.samAccountName}
		elseif (compare $da.LogonWorkstations $dcsnetbios) { $baddalogon += $da.samAccountName }
	}
	
	if ($baddalogon) {
		$dacsv = $baddalogon -join ","
		Write-Message "The following DAs are allowed to logon to non-DCs: $dacsv. This finding is crucial as it allows attackers to pull DA password hashes from those machines. Best practice is to restrict DA logins to just DCs." "error" }
	else {Write-Message "DA logons are restricted to just DCs. Awesome!" "success"}
	
	Write-Host "`n"
	Write-Host "If you see any " -NoNewline 
	Write-Host "yellow" -ForegroundColor Yellow -NoNewline
	Write-Host " or " -NoNewline 
	Write-Host "red" -ForegroundColor Red -NoNewline
	Write-Host ", you should consider running the 'Secure Domain Admins' option.`n"
	
	Write-Message "Password Policy best practices: http://technet.microsoft.com/en-us/magazine/ff741764.aspx"
	Write-Message "Configuring a Password Policy: http://technet.microsoft.com/en-us/library/cc875814.aspx"
	Write-Message "`nDone!`n" "info"
	
	Read-Host "Press the Any key to continue..."
}

Function ProcessMenuChoice {
	Param( $userchoice ) 
	switch ($userchoice) {
		"1" { 
			EvalDAs
			Menu
		}
		"2" { }
		"3" { }
		"4" { }
		"5" { }
		"6" { Write-Help }
		"7" { exit }
		default { 
			Write-Message "Please enter a valid option`n`n" "warning"
			$optionstring = [string]::Format("{0,$windowoffset}", "Please select an option")
			ProcessMenuChoice (Read-Host $optionstring)
		}
	}
}

############### MAIN SCRIPT BLOCK ###############

# Perform all PreReq Checks
DoPreReqs

#Load the Menu
$userchoice = Menu
ProcessMenuChoice $userchoice

	



					

