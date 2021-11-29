# add, modify, remove OnlinePSTNGateway Settings"
New-CsOnlinePSTNGateway -Identity $sbc1 -SipSignalingPort 5067 -FailoverTimeSeconds 5 -ForwardCallHistory 1 -ForwardPai 1 -SendSipOptions 1 -MaxConcurrentSessions 10 -Enabled 1 -MediaBypass 1
New-CsOnlinePSTNGateway -Identity $sbc2 -SipSignalingPort 5067 -FailoverTimeSeconds 5 -ForwardCallHistory 1 -ForwardPai 1 -SendSipOptions 1 -MaxConcurrentSessions 10 -Enabled 1 -MediaBypass 1
New-CsOnlinePSTNGateway -Identity $sbc3 -SipSignalingPort 5067 -FailoverTimeSeconds 10 -ForwardCallHistory 1 -ForwardPai 1 -SendSipOptions 1 -MaxConcurrentSessions 10 -Enabled 1 -MediaBypass 1

Set-CsOnlinePSTNGateway -Identity $sbc1 -SipSignalingPort 5067 -FailoverTimeSeconds 5 -ForwardCallHistory 1 -ForwardPai 1 -SendSipOptions 1 -MaxConcurrentSessions 10 -Enabled 1 -MediaBypass 1
Set-CsOnlinePSTNGateway -Identity $sbc2 -SipSignalingPort 5067 -FailoverTimeSeconds 5 -ForwardCallHistory 1 -ForwardPai 1 -SendSipOptions 1 -MaxConcurrentSessions 10 -Enabled 1 -MediaBypass 1
Set-CsOnlinePSTNGateway -Identity $sbc3 -SipSignalingPort 5067 -FailoverTimeSeconds 10 -ForwardCallHistory 1 -ForwardPai 1 -SendSipOptions 1 -MaxConcurrentSessions 10 -Enabled 1 -MediaBypass 1

Remove-CsOnlinePSTNGateway -Identity $sbc1;
Remove-CsOnlinePSTNGateway -Identity $sbc2;
Remove-CsOnlinePSTNGateway -Identity $sbc3;

# add, modify, remove OnlinePstnUsage + VoiceRoutingPolicy
Set-CsOnlinePstnUsage -Identity global -Usage @{add=$PstnUsageNameLoc1, $PstnUsageNameLoc2, $PstnUsageNameLoc1Bak, $PstnUsageNameLeastCost}
Set-CsOnlinePstnUsage -Identity global -Usage @{remove=$PstnUsageNameLoc1, $PstnUsageNameLoc2, $PstnUsageNameLoc1Bak, $PstnUsageNameLeastCost}

New-CsOnlineVoiceRoutingPolicy $VoiceRoutePolicyNameLoc1 -OnlinePstnUsages $PstnUsageNameLoc1, $PstnUsageNameLoc1Bak, $PstnUsageNameLeastCost;
New-CsOnlineVoiceRoutingPolicy $VoiceRoutePolicyNameLoc2 -OnlinePstnUsages $PstnUsageNameLoc2, $PstnUsageNameLeastCost;
Remove-CsOnlineVoiceRoutingPolicy $VoiceRoutePolicyNameLoc1;
Remove-CsOnlineVoiceRoutingPolicy $VoiceRoutePolicyNameLoc2;

# add, modify, remove OnlineVoiceRoute
New-CsOnlineVoiceRoute -Identity $VoiceRoute1 -Priority 0 -Description $desc1 -OnlinePstnGatewayList $sbc1, $sbc2 -NumberPattern $PatternLoc1 -OnlinePstnUsage $PstnUsageNameLoc1, $PstnUsageNameLeastCost;
New-CsOnlineVoiceRoute -Identity $VoiceRoute2 -Priority 1 -Description $desc2 -OnlinePstnGatewayList $sbc3 -NumberPattern $PatternLoc1 -OnlinePstnUsage $PstnUsageNameLoc1Bak;
New-CsOnlineVoiceRoute -Identity $VoiceRoute3 -Priority 2 -Description $desc3 -OnlinePstnGatewayList $sbc3 -NumberPattern $PatternLoc2 -OnlinePstnUsage $PstnUsageNameLoc2, $PstnUsageNameLeastCost;
New-CsOnlineVoiceRoute -Identity $VoiceRoute4 -Priority 4 -Description $desc5 -OnlinePstnGatewayList $sbc1, $sbc2, $sbc3 -NumberPattern $PatternSBC2SBC -OnlinePstnUsage $PstnUsageNameLoc2;

Set-CsOnlineVoiceRoute -Identity $VoiceRoute1 -Priority 0 -Description $desc1 -OnlinePstnGatewayList $sbc1, $sbc2 -NumberPattern $PatternLoc1 -OnlinePstnUsage $PstnUsageNameLoc1;
Set-CsOnlineVoiceRoute -Identity $VoiceRoute2 -Priority 1 -Description $desc2 -OnlinePstnGatewayList $sbc3 -NumberPattern $PatternLoc1 -OnlinePstnUsage $PstnUsageNameLoc1;
Set-CsOnlineVoiceRoute -Identity $VoiceRoute3 -Priority 2 -Description $desc3 -OnlinePstnGatewayList $sbc3 -NumberPattern $PatternLoc2 -OnlinePstnUsage $PstnUsageNameLoc1;
Set-CsOnlineVoiceRoute -Identity $VoiceRoute4 -Priority 4 -Description $desc5 -OnlinePstnGatewayList $sbc1, $sbc2, $sbc3 -NumberPattern $PatternSBC2SBC -OnlinePstnUsage $PstnUsageNameLoc2;

Remove-CsOnlineVoiceRoute -Identity $VoiceRoute1;
Remove-CsOnlineVoiceRoute -Identity $VoiceRoute2;
Remove-CsOnlineVoiceRoute -Identity $VoiceRoute3;
Remove-CsOnlineVoiceRoute -Identity $VoiceRoute4;

# assign VoiceRoutingPolicy to your users
Get-CsOnlineUser -Identity "john.doe@contoso.com" | Grant-CsTeamsUpgradePolicy -PolicyName UpgradeToTeams
Set-CsUser "john.doe@contoso.com" -EnterpriseVoiceEnabled $true -HostedVoiceMail $true -OnPremLineURI "tel:$LineUri"

Grant-CsOnlineVoiceRoutingPolicy -PolicyName $VoiceRoutePolicyNameLoc1 -Identity "john.doe@contoso.com";
Grant-CsOnlineVoiceRoutingPolicy -PolicyName $VoiceRoutePolicyNameLoc2 -Identity "jane.doe@contoso.com";
