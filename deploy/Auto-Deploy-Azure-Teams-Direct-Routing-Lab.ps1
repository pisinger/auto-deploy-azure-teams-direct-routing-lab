# https://github.com/pisinger

<#	
	++ The main idea of this setup is to use Direct Routing without going for real/public SIP Trunk (Telco) and PSTN connectivity, instead we make use of number manipulation and re-routing logic (looping). In fact, we do route calls from Teams to the SBC and then looping/routing them back to Teams. The key is to avoid RNL (Reverse Number Lookup) when dialing numbers - this is where number manipulation comes into place.
	
	Script will do the following:
		1) Deploying Azure Resource Group with pre-defined network config
		2) Creating 3 SBCs (AudioCodes) including ready-to-use config INI file (with prepared profile for ITSP in case you want to go for real SIP Trunk). The config file then needs to get imported manually.
		3) Creating 1 Windows Admin Machine for Syslog, as well providing you a hub to do SBC administration.
		4) Configuring Teams Direct Routing Setup (PstnUsage, VoiceRoutingPolicy, PstnOnlineGateways) -> giving you the commands ready to run via Teams PowerShell manually
		5) Manually assigning needed Teams calling policies to test users

	Prerequisites:
		- Azure Subscription
		- Office 365 Tenant with Phone System License (including provisioned Teams Users)
		- Custom Domain registered with O365 and with access to DNS -> needed to add public A-Records per SBC
		- Public Certificate -> personal recommendation is using wildcard such as *.contoso.com
	
	Note: Make sure the user is TeamsOnly and proper licenses are assigned
	
	Azure PowerShell Module -> Install-Module -Name Az -> Connect-AzAccount + Select-AzSubscription
	Teams PowerShell Module -> Install-Module -Name MicrosoftTeams -> Connect-MicrosoftTeams

	https://docs.microsoft.com/en-us/microsoftteams/direct-routing-enable-users	
	SBC Setup: https://www.audiocodes.com/media/13250/mediant-virtual-edition-sbc-for-microsoft-azure-installation-manual-ver-72.pdf
	
	** Lab install will take approx. 6min **
#>

#region definitions
# --------------------------- DEFINITIONS ---------------------------
# fixed - Do not change
$templateAzure			= Get-Content $($PSScriptRoot + "\templates\TEMPLATE.json")	# dont change
$TemplateAzurePrep		= $($PSScriptRoot + "\templates\template-custom.json")		# dont change
$TemplateRdpFile		= $($PSScriptRoot + "\templates\admin-syslog01.rdp")		# dont change
$TemplateConfigTeams 	= $($PSScriptRoot + "\templates\TEMPLATE-ConfigTeams.ps1")	# dont change
$TemplateConfigSBC 		= $($PSScriptRoot + "\templates\TEMPLATE-ConfigSBC.ini")	# dont change
$RandomRdpPort 			= Get-Random -Minimum 15000 -Maximum 63000

# azure resource group
$ResourceGroupName 	= "TEAMS-DR-POC3"
$Location 			= "germanywestcentral"		# Get-AzLocation | select location
$VMSizeSBC 			= "Standard_B1ms"
$VMSizeAdmin		= "Standard_B2s"
$StorageAccountName = $("drstorage" + $(Get-Random -Minimum 10000 -Maximum 99999))

# machine names - SBS machine name will also be used for public dns
$SipDomain 		= Read-Host "Enter SIP Domain (SBC FQDN)"
$AdminUserName	= Read-Host "Choose Azure Admin User Name" 
$AdminMachine 	= "admin-syslog01"
$SBCs 			= ("sbc1","sbc2","sbc3")

# dummy number: +77 33 5555 ext
[string]$PstnLocation1 			= "DE"
[int]$DummyNumberCountryCode1	= 49
[int]$DummyNumberAreaAndSub1	= 5555

[string]$PstnLocation2 			= "UK"
[int]$DummyNumberCountryCode2	= 44
[int]$DummyNumberAreaAndSub2	= 6666

# Teams Calling
$PstnUsageNameLoc1 			= $("PSTN-USAGE-" + $PstnLocation1)
$PstnUsageNameLoc1Bak		= $("PSTN-USAGE-" + $PstnLocation1 + "-VIA-" + $PstnLocation2)
$PstnUsageNameLoc2 			= $("PSTN-USAGE-" + $PstnLocation2)
$PstnUsageNameLeastCost		= "PSTN-USAGE-LEAST-COST"
$VoiceRoutePolicyNameLoc1	= $("VOICE-ROUTING-POLICY-" + $PstnLocation1)
$VoiceRoutePolicyNameLoc2	= $("VOICE-ROUTING-POLICY-" + $PstnLocation2)

#endregion

#region functions
function Connect-AzureSubcription {	
    Connect-AzAccount
    $Subscriptions = Get-AzSubscription
	
	Write-Host "Please select the Azure Subscription: " -ForegroundColor GREEN
	FOR ($i = 0; $i -lt $Subscriptions.Count; $i++) {	Write-Host "$($i+1): $($Subscriptions[$i].Name)"}	
    
	[int]$number = Read-Host "Select Azure Subscription: "
    Write-Host ""	
    Write-Host "You've selected $($Subscriptions[$number-1].Name)." -ForegroundColor GREEN

    $subscriptionId = $Subscriptions
    Select-AzSubscription -SubscriptionName $($Subscriptions[$number-1].Name)
}

function Prepare-AzureTemplate (){
	
	$templateAzure = $templateAzure.Replace('"admin-syslog_',('"' + $AdminMachine + "_").ToLower())
	$templateAzure = $templateAzure.Replace('"sbc1_',('"' + $SBCs[0] + "_").ToLower())
    $templateAzure = $templateAzure.Replace('"sbc2_',('"' + $SBCs[1] + "_").ToLower())
    $templateAzure = $templateAzure.Replace('"sbc3_',('"' + $SBCs[2] + "_").ToLower())
    $templateAzure = $templateAzure.Replace("Your_Azure_Region",($location).ToLower())
	$templateAzure = $templateAzure.Replace("3389",$RandomRdpPort)
	
	$templateAzure | out-file -FilePath $TemplateAzurePrep -Force
}

function New-AzureNetwork (){

	New-AzResourceGroup -Name $ResourceGroupName -Location $Location
	New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $TemplateAzurePrep
}

function New-AzureStorageAccount {	
	
	$StorageAccount = New-AzStorageAccount `
	  -Location $Location `
	  -ResourceGroupName $ResourceGroupName `
	  -Type "Standard_LRS" `
	  -Name $storageAccountName
	  
	Set-AzCurrentStorageAccount -StorageAccountName $storageAccountName -ResourceGroupName $ResourceGroupName
}

function Deploy-AzureSBC (){
	param ([string]$VMName,	[string]$VMSize, $Creds)
	
	# vm pre-config
	$VM = New-AzVMConfig -VMName $VMName -VMSize $VMSize
	
	# attach interface
	$Interface = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "*$VMName*"
	Add-AzVMNetworkInterface -VM $VM -Id $Interface.Id

	# Accept Marcketplace terms 
	Get-AzMarketplaceTerms -Publisher "audiocodes" -product "mediantsessionbordercontroller" -Name "mediantvirtualsbcazure" | Set-AzMarketplaceTerms -Accept
	
	Set-AzVMSourceImage -VM $VM -PublisherName "audiocodes" -Offer "mediantsessionbordercontroller" -Skus "mediantvirtualsbcazure" -Version latest
	Set-AzVMPlan -VM $VM -Name "mediantvirtualsbcazure" -Publisher "audiocodes" -Product "mediantsessionbordercontroller"
	Set-AzVMOSDisk -VM $VM -Name $($VMName + "_OsDisk") -DiskSizeInGB 10 -StorageAccountType "Standard_LRS" -CreateOption fromImage -Linux
	#Set-AzVMBootDiagnostic -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Enable
	Set-AzVMOperatingSystem -VM $VM -Linux -ComputerName $VM Name -Credential $Creds

	# create vm
	New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM -AsJob
}

function Deploy-AdminMachine () {
	param ([string]$VMName, [string]$VMSize, $Creds)
	
	$VM = New-AzVMConfig -VMName $VMName -VMSize $VMSize
	
	$Interface = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name "*$VMName*"
	Add-AzVMNetworkInterface -VM $VM -Id $Interface.Id	
	
	#Get-AzVMImageSku -Location "West Europe" -Offer WindowsServer -PublisherName MicrosoftWindowsServer
	Set-AzVMSourceImage -VM $VM -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2019-Datacenter' -Version latest
	Set-AzVMOperatingSystem -VM $VM -Windows -ComputerName $VMName -Credential $Creds -ProvisionVMAgent -EnableAutoUpdate	
	Set-AzVMOSDisk -VM $VM -Name $($VMName + "_OsDisk") -StorageAccountType "StandardSSD_LRS" -CreateOption FromImage
	#Set-AzVMBootDiagnostic -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Enable
	
	New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM -AsJob
}

function Prepare-SbcConfigFile () {
	
	$DummyNumberCountryCode1 = "+" + $DummyNumberCountryCode1
	$DummyNumberCountryCode2 = "+" + $DummyNumberCountryCode2
	$CountryCodeDigits1 = (($DummyNumberCountryCode1 + $DummyNumberAreaAndSub1) | Measure-Object -Character).Characters
	$CountryCodeDigits2 = (($DummyNumberCountryCode2 + $DummyNumberAreaAndSub2) | Measure-Object -Character).Characters
	
	$SBCs | FOREACH {
	
		$VmName = $_
		
		IF ($VmName -eq $SBCs[0] -or $VmName -eq $SBCs[1]){$DNS = '10.1.0.13, 0.0.0.0'}
		ELSE {$DNS = '10.1.0.11, 10.1.0.12'}	

		$InternalIP = (Get-AzNetworkInterface -Name "$VMName*" | Get-AzNetworkInterfaceIpConfig).PrivateIpAddress
		
		$FileNameINI = $VMName + ".ini"
		$ini = Get-Content $TemplateConfigSBC
		$ini = $ini -replace ("contoso.com",$SipDomain)
		$ini = $ini -replace ('10.1.0.11, 10.1.0.12',$DNS)
		$ini = $ini -replace ("mysbc1",$SBCs[0])
		$ini = $ini -replace ("mysbc2",$SBCs[1])
		$ini = $ini -replace ("mysbc3",$SBCs[2])
		$ini = $ini -replace ("mysbc",$VMName)
		$ini = $ini -replace ('\+49',$DummyNumberCountryCode1)
		$ini = $ini -replace ('5555',$DummyNumberAreaAndSub1)
		$ini = $ini -replace ('\+44',$DummyNumberCountryCode2)
		$ini = $ini -replace ('6666',$DummyNumberAreaAndSub2)
		$ini = $ini -replace ("DIGITS1",$CountryCodeDigits1)
		$ini = $ini -replace ("DIGITS2",$CountryCodeDigits2)
		$ini = $ini -replace ('Location1',$PstnLocation1)
		$ini = $ini -replace ('Location2',$PstnLocation2)
		$ini = $ini -replace ("localhost",$InternalIP)		
		$ini | Out-file $($PSScriptRoot + "\config\" + $FileNameINI)
	}
}

function Prepare-TeamsDirectRoutingConfig () {
	
	$PstnUsageNameLoc1 			= '"' + $PstnUsageNameLoc1 + '"'
	$PstnUsageNameLoc1Bak		= '"' + $PstnUsageNameLoc1Bak + '"'
	$PstnUsageNameLoc2 			= '"' + $PstnUsageNameLoc2 + '"'
	$PstnUsageNameLeastCost 	= '"' + $PstnUsageNameLeastCost + '"'	
	$VoiceRoutePolicyNameLoc1 	= '"' + $VoiceRoutePolicyNameLoc1 + '"'
	$VoiceRoutePolicyNameLoc2 	= '"' + $VoiceRoutePolicyNameLoc2 + '"'
	
	$PatternLoc1		= "^\+(99|49)(\d*)$";
	$PatternLoc2 		= "^\+(98|44)(\d*)$";
	$PatternSBC2SBC 	= "^\+(798|799)(\d*)$";
	$PatternStrict 		= "^\+(798)(\d*)$";	
	$PatternLoc1 		= $PatternLoc1 -replace 49,$DummyNumberCountryCode1; $PatternLoc1 = '"' + $PatternLoc1 + '"'		
	$PatternLoc2 		= $PatternLoc2 -replace 49,$DummyNumberCountryCode1; $PatternLoc2 = $PatternLoc2 -replace 44, $DummyNumberCountryCode2; $PatternLoc2 = '"' + $PatternLoc2 + '"'	
	$PatternSBC2SBC = '"' + $PatternSBC2SBC + '"'	
	$PatternStrict 	= '"' + $PatternStrict + '"'
	
	$sbc1 = '"' + $sbcs[0] + "." + $SipDomain + '"'
	$sbc2 = '"' + $sbcs[1] + "." + $SipDomain + '"'
	$sbc3 = '"' + $sbcs[2] + "." + $SipDomain + '"'
	
	$VoiceRoute1 = '"ROUTE' + "-" + $PstnLocation1 + '-PRIMARY-HA"'; 	$desc1 = '"Primary Route to sbc1 and sbc2"'
	$VoiceRoute2 = '"ROUTE' + "-" + $PstnLocation1 + '-BACKUP-DR"'; 	$desc2 = '"Backup Route to sbc3"'
	$VoiceRoute3 = '"ROUTE' + "-" + $PstnLocation2 + '-PRIMARY"'; 		$desc3 = '"Primary Route to sbc3"'
	$VoiceRoute4 = '"ROUTE' + "-FORCED" + '-SBC-TO-SBC"'; 				$desc5 = '"Route via SBC to SBC"'
	
	$config = Get-Content $TemplateConfigTeams
	$config = $config -replace ('\$sbc1',$Sbc1)
	$config = $config -replace ('\$sbc2',$Sbc2)
	$config = $config -replace ('\$sbc3',$Sbc3)
	$config = $config -replace ('\$PatternLoc1',$PatternLoc1)
	$config = $config -replace ('\$PatternLoc2',$PatternLoc2)
	$config = $config -replace ('\$PatternSBC2SBC',$PatternSBC2SBC)
	$config = $config -replace ('\$PatternStrict',$PatternStrict)
	$config = $config -replace ('\$PstnUsageNameLoc1Bak',$PstnUsageNameLoc1Bak)
	$config = $config -replace ('\$PstnUsageNameLoc2',$PstnUsageNameLoc2)
	$config = $config -replace ('\$PstnUsageNameLoc1',$PstnUsageNameLoc1)
	$config = $config -replace ('\$PstnUsageNameLeastCost',$PstnUsageNameLeastCost)
	$config = $config -replace ('\$VoiceRoutePolicyNameLoc1',$VoiceRoutePolicyNameLoc1)
	$config = $config -replace ('\$VoiceRoutePolicyNameLoc2',$VoiceRoutePolicyNameLoc2)		
	$config = $config -replace ('\$VoiceRoute1',$VoiceRoute1)
	$config = $config -replace ('\$VoiceRoute2',$VoiceRoute2)
	$config = $config -replace ('\$VoiceRoute3',$VoiceRoute3)
	$config = $config -replace ('\$VoiceRoute4',$VoiceRoute4)
	$config = $config -replace ('\$VoiceRoute4',$VoiceRoute4)	
	$config = $config -replace ('\$desc1',$desc1)
	$config = $config -replace ('\$desc2',$desc2)
	$config = $config -replace ('\$desc3',$desc3)
	$config = $config -replace ('\$desc4',$desc4)
	$config = $config -replace ('\$desc5',$desc5)	
	$config | Out-file $($PSScriptRoot + "\config\OPEN-ConfigTeams.ps1")
}

function Remove-TeamsDirectRoutingSetup () {
	# not used yet
	param ([array]$SBCS, [string]$PstnUsageNameLoc, [string]$VoiceRouteName)
	
	Remove-CsOnlineVoiceRoute -Identity $VoiceRouteName
	
	Set-CsOnlinePstnUsage -Identity global -Usage @{remove=$PstnUsageNameLoc}	
	Get-CsOnlineUser | where OnlineVoiceRoutingPolicy -like $VoiceRouteName | Grant-CsOnlineVoiceRoutingPolicy -PolicyName ""
	Remove-CsOnlineVoiceRoutingPolicy $VoiceRouteName
	
	Foreach ($sbc in $sbcs){
		Remove-CsOnlinePSTNGateway -Identity $sbc".contoso.com"
	}
}
	
function Create-RdpFileAdmin {
	param ([ipaddress]$PublicIP, [int]$RandomPort)
	
	$config = Get-Content $TemplateRdpFile
	$config = $config -replace ('7.7.7.7',$PublicIP)
	$config = $config -replace ('3389',$RandomPort)	
	$config | Out-file $($PSScriptRoot + "\config\admin-syslog.rdp")
}

#endregion

#region main
# ------------------- MAIN ------------------------
$StopWatch = New-Object System.Diagnostics.Stopwatch
$StopWatch.Start()
#--------------------------------------------------
#$Password = Read-host "Choose Password" | ConvertTo-SecureString -Force -AsPlainText
$Password = Read-host "Choose Password" -AsSecureString
$Creds = New-Object PSCredential($AdminUserName, $Password)	

# create config folder if not yet exist
IF (!(Get-Childitem $($PSScriptRoot + "\config") -ErrorAction SilentlyContinue)) {
	New-Item -Path $($PSScriptRoot + "\config") -Type Directory
}

Prepare-AzureTemplate
New-AzureNetwork
New-AzureStorageAccount

Deploy-AdminMachine $AdminMachine $VMSizeAdmin $Creds
$SBCS | ForEach-Object {Deploy-AzureSBC $_ $VMSizeSBC $Creds}

Prepare-SbcConfigFile 
Prepare-TeamsDirectRoutingConfig 
#--------------------------------------------------
# cleanup jobs
While (Get-Job -State "Running") {Get-Job -State "Completed" | Receive-Job;	Start-Sleep 30}; Remove-Job * 
#--------------------------------------------------
# get public IPs needed for DNS
"" | Out-File $($PSScriptRoot + "\config\OPEN-PublicDnsRequired.txt")
$SBCS | foreach {$PublicIP = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "*$_*").IpAddress; $PublicIP + "`t" + "$_.$SipDomain" | Out-File -Append $($PSScriptRoot + "\config\OPEN-PublicDnsRequired.txt")}
#--------------------------------------------------
# set custom rdp port for admin machine
Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $AdminMachine -CommandId SetRDPPort -Parameter @{"RDPPORT" = $RandomRdpPort}
$AdminMachinePublicIP = (Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name "*$AdminMachine*").IpAddress
#--------------------------------------------------
$($AdminMachinePublicIP + ":" + $RandomRdpPort) | out-file $($PSScriptRoot + "\config\Your-Random-RDP-Port.txt")
Create-RdpFileAdmin $AdminMachinePublicIP $RandomRdpPort
#--------------------------------------------------
# post setup admin machine
Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $AdminMachine -CommandId 'RunPowerShellScript' -ScriptPath $($PSScriptRoot + "\templates\admin-syslog01-post-setup.ps1") -Parameter @{UserName = $Creds.Username}
#--------------------------------------------------

$StopWatch.Stop()
$StopWatch.Elapsed.TotalSeconds
#endregion
