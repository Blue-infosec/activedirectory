# PreRequisites
#	1. User running the script must be a Domain Admin
#	2. ActiveDirectory and GroupPolicy modules must be available from RSAT. http://www.microsoft.com/en-us/download/details.aspx?id=7887
#	3. Machine running the script must be a domain member.


############### GLOBAL VARS ###############

#Current User Name
$struser = $env:USERNAME

#Current Domain Name
$strdomain = $env:USERDOMAIN

#Current Domain Object
$domain = $null

#Current User Object
$currentuser = $null

# XML based list of domain GPOs
[xml]$gpos = $null

# XML based RSOP data for both user & computer
[xml]$rsop = $null


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

	#Domain Admin Check
	if ($currentuser.MemberOf | Select-String "CN=Domain Admins") {
		Write-Message "Current user is a Domain Admin." "prereq"
	} else { 
		Write-Message "Bad news. The user running this script must be a Domain Admin. Exiting.." "error"
		exit
	}
	
	# Export all gpo settings to xml
	try {
		Get-GPOReport -All -Path "gpodata.xml" -ReportType Xml
		$global:gpos = gc "gpodata.xml"
		Write-Message "Successfully exported GPOs from domain $strdomain" "prereq"
	} catch [Exception] {
		$err = $_.Exception.Message
		Write-Message "Failed to export GPOs from domain $strdomain. Error: $err. Exiting..." "error"
		exit
	}
	
	#Export RSOP data to xml
	try {
		Get-GPResultantSetOfPolicy -Path "rsopdata.xml" -ReportType Xml | Out-Null
		$global:rsop = gc "rsopdata.xml"
		Write-Message "Successfully exported & loaded RSOP data." "prereq"
	} catch [Exception] {
		$err = $_.Exception.Message
		Write-Message "Failed to export RSOP data for current user/machine. Error: $err. Exiting..." "error"
		exit
	}
}

Function Write-Centered {
	Param(	[string] $message,
			[string] $color = "black")
	$offsetvalue = ([Console]::WindowWidth / 2) + ($message.Length / 2)
	Write-Host ("{0,$offsetvalue}" -f $message) -ForegroundColor $color
}

Function Menu {
	Write-Centered "############ SecureThisDomain ############" "Magenta"
}

Function Write-Help {
	Write-Message	"

	***** SECURETHISDOMAIN *****

	SecureThisDomain.ps1 uses Group Policy to create a tightly controlled environment 
	for your Domain Controllers (DC) and your Domain Admins (DA). Both DCs and DAs 
	are high value targets for pentesters and hackers alike and, if compromised, basically 
	represent ownage of your domain/network. This script is designed to seriously 
	slow them down, allowing you more time to detect and mitigate internal threats against your AD environment.

	* It will create a GPO called 'Core AD Security Policy' and add the following settings to it (with your permission):
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


############### MAIN SCRIPT BLOCK ###############

# Perform all PreReq Checks
DoPreReqs

[Environment]::NewLine

Menu


					

