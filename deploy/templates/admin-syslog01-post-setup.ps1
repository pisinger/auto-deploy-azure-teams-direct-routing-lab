
param ([string]$UserName)

# create folder and copy files
$Path = $("c:\TEMP\")
New-Item -Path $Path -ItemType Directory

# download + install edge
$response = Invoke-WebRequest -Uri "https://edgeupdates.microsoft.com/api/products?view=enterprise" -Method Get -ContentType "application/json" -ErrorAction Stop -UseBasicParsing
$uri = (((ConvertFrom-Json $([String]::new($response.Content))).releases | where-object Platform -eq "Windows" | where-object Architecture -eq "x64" | where-object Artifacts -like "*MicrosoftEdgeEnterpriseX64.msi*") | select-object -First 1).Artifacts.Location
(New-Object System.Net.WebClient).DownloadFile($uri,$($Path + "MicrosoftEdgeEnterpriseX64.msi"))
Start-Process $($Path + "MicrosoftEdgeEnterpriseX64.msi") -ArgumentList "/quiet"

# download syslog + iniEdit
$uri = "http://redirect.audiocodes.com/install/syslogViewer/syslogViewer-setup.exe"
(New-Object System.Net.WebClient).DownloadFile($uri,$($Path + "syslogViewer-setup.exe"))

$uri = "http://redirect.audiocodes.com/install/iniedit/iniedit-setup.exe"
(New-Object System.Net.WebClient).DownloadFile($uri,$($Path + "iniedit-setup.exe"))

# download + install Teams Client
$Uri = (Invoke-WebRequest "https://teams.microsoft.com/downloads/DesktopURL?&env=production&plat=windows&arch=x64" -UseBasicParsing).Content
(New-Object System.Net.WebClient).DownloadFile($uri,$($Path + "Teams.exe"))
#Start-Process $($Path + "Teams.exe") -ArgumentList "-s"

# add inbound firewall rule for syslog
New-NetFirewallRule -Name "SYSLOG" -DisplayName "SYSLOG" -Enabled True -Direction Inbound -Action Allow -Protocol UDP -LocalPort 514

# create SBC shortcuts desktop
$SourceFilePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

$ShortcutPath = $($Path + "MsEdge_sbc1.lnk")
$WScriptObj = New-Object -ComObject ("WScript.Shell")
$shortcut = $WscriptObj.CreateShortcut($ShortcutPath)
$shortcut.Arguments = "https://10.1.0.11"
$shortcut.TargetPath = $SourceFilePath
$shortcut.Save()

$ShortcutPath = $($Path + "MsEdge_sbc2.lnk")
$WScriptObj = New-Object -ComObject ("WScript.Shell")
$shortcut = $WscriptObj.CreateShortcut($ShortcutPath)
$shortcut.Arguments = "https://10.1.0.12"
$shortcut.TargetPath = $SourceFilePath
$shortcut.Save()

$ShortcutPath = $($Path + "MsEdge_sbc3.lnk")
$WScriptObj = New-Object -ComObject ("WScript.Shell")
$shortcut = $WscriptObj.CreateShortcut($ShortcutPath)
$shortcut.Arguments = "https://10.1.0.13"
$shortcut.TargetPath = $SourceFilePath
$shortcut.Save()
