$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
[string]$LogFile = "$ScriptPath\Logs\$((get-date).ToString('yyyy-MM-dd_hh-mm')).txt"
If (-Not(Test-Path -Path "$ScriptPath\Logs")){New-Item -ItemType directory -path "$ScriptPath\Logs" -Force | Out-Null}
    Get-ChildItem -Path "$ScriptPath\Logs" | Where {$_.PSisContainer -eq $false -and $_.LastWriteTime -lt (Get-date).AddDays(-5)} | Remove-Item -Force
    New-Item -ItemType file -path $LogFile -Force | Out-Null
#-----------------------------------------------------------------------
$To = 'Email@SomeWhere.com'
$From = 'Email@SomeWhere.com'
$Subject = "DFSr BackLog Count $((get-date).ToString('MM/dd/yyyy'))"
$MailServer = 'Mail.SomeWhere.com'
#-----------------------------------------------------------------------
$a = "<style>"
$a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$a = $a + "TH{border-width: 1px;padding: 0px;border-style: solid;border-color: black;background-color:DarkGray;text-align:center}"
$a = $a + "TD{border-width: 1px;padding: 0px;border-style: solid;border-color: black;text-align:center}"
$a = $a + "TR:nth-child(odd) {background: #E6E6E6}"
$a = $a + "</style>"
#-----------------------------------------------------------------------
$Domains = 'Domain1','Domain2'
$Global:OutPut = @()
Foreach ($Domain in $Domains){
Out-File -Append $LogFile -InputObject "$Domain" -Force
$RepGroupCommand = "dfsradmin rg list /Domain:'" + $Domain + "' /attr:rgname"
$NetRepGroupNames = Invoke-Expression -Command $RepGroupCommand | Where {-not($_ -like 'RgName' -or $_ -like "" -or $_ -like 'Domain System Volume' -or $_ -like 'Command completed successfully.')}
If($LASTEXITCODE -ne 0 -or $LASTEXITCODE -eq $Null){Out-File -Append $LogFile -InputObject "**ERROR** Unable to retrieve a list of Replication Groups from $Domain **ERROR**`r`n`tCommand - dfsradmin rg list /Domain:$Domain /attr:rgname" -Force
    #Write-Warning 'Domain - ERROR'
    $Data = New-Object psobject
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReplication Group&nbsp' -Value 'Could not retrieve'
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspFolder Name&nbsp' -Value 'replication'
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspSending Member&nbsp' -Value ' groups from'
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReceiving Member&nbsp' -Value $Domain
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspBack Log Count&nbsp' -Value '**ERROR**'
    $Global:OutPut += $Data
    $LASTEXITCODE = 0
    }# End of $LastExitCode 'Domain'
    Foreach ($NetRepGroupName in $NetRepGroupNames){
        Out-File -Append $LogFile -InputObject "`t$NetRepGroupName -  $(Get-date -Format hh:mm:ss)" -Force
        $FolderListCommand = "DfsrAdmin RF List /Domain:'" + $Domain + "' /RgName:'" + $NetRepGroupName + "' /attr:RfName"
        $FolderList = Invoke-Expression -Command $FolderListCommand | Where {-not($_ -like 'RfName' -or $_ -like "" -or $_ -like 'Command completed successfully.')}
        If($LASTEXITCODE -ne 0){Out-File -Append $LogFile -InputObject "**ERROR** Unable to retrieve a list of Replication Folders for $NetRepGroupName **ERROR**`r`n`tCommand - DfsrAdmin RF List /Domain:$Domain /RgName:$NetRepGroupName /attr:RfName" -Force
            #Write-Warning 'Folder - ERROR'
            $Data = New-Object psobject
            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReplication Group&nbsp' -Value 'Could not retrieve'
            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspFolder Name&nbsp' -Value 'replication'
            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspSending Member&nbsp' -Value ' folders from'
            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReceiving Member&nbsp' -Value $NetRepGroupName
            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspBack Log Count&nbsp' -Value '**ERROR**'
            $Global:OutPut += $Data
            $LASTEXITCODE = 0
            }# End of $LastExitCode 'Folder'
        Foreach ($Folder in $FolderList){
            Out-File -Append $LogFile -InputObject "`t`t$Folder" -Force
            $MembersCommand = "DfsrAdmin Conn list /Domain:'" + $Domain + "' /RgName:'" + $NetRepGroupName + "' '/attr:SendMem,RecvMem'"
            $Members = Invoke-Expression -Command $MembersCommand | Where {-not($_ -like 'Sendmem*RecvMem' -or $_ -like "" -or $_ -like 'Command completed successfully.')}
            If($LASTEXITCODE -ne 0){Out-File -Append $LogFile -InputObject "**ERROR** Unable to retrieve a list of Servers for $NetRepGroupName **ERROR**`r`n`tCommand - DfsrAdmin Conn list /Domain:$Domain /RgName:$NetRepGroupName '/attr:SendMem,RecvMem'" -Force
                #Write-Warning 'Members - ERROR'
                $Data = New-Object psobject
                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReplication Group&nbsp' -Value 'Could not retrieve'
                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspFolder Name&nbsp' -Value 'replication'
                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspSending Member&nbsp' -Value ' members from'
                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReceiving Member&nbsp' -Value $NetRepGroupName
                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspBack Log Count&nbsp' -Value '**ERROR**'
                $Global:OutPut += $Data
                $LASTEXITCODE = 0
                }# End of $LastExitCode 'Members'
            Foreach ($Member in $Members){
                $SplitMember = $Member -Split ' {2,}'
                Out-File -Append $LogFile -InputObject "`t`t`t$($SplitMember[0]) --> $($SplitMember[1])" -Force
                $BacklogCommand = "Dfsrdiag backlog /Domain:'" + $Domain + "' /ReceivingMember:'" + $($SplitMember[1]) + "' /SendingMember:'" + $($SplitMember[0]) + "' /RgName:'" + $NetRepGroupName + "' /RFName:'" + $Folder + "'"
                $BackLogCount = Invoke-Expression -Command $BacklogCommand | Where {$_ -like '*Backlog File Count:*'}
                If($LASTEXITCODE -ne 0){
                    $RetryCount = 1
                    Do{
                        Sleep -Seconds 5
                        Out-File -Append $LogFile -InputObject "`t`t`tError Retrying - $RetryCount - $(Get-date -Format hh:mm:ss)"
                        $LASTEXITCODE = 0
                        $BackLogCount = Invoke-Expression -Command $BacklogCommand | Where {$_ -like '*Backlog File Count:*'}
                        $RetryCount++
                    }# End of While
                    Until($RetryCount -eq 11 -or $LASTEXITCODE -eq 0)
                }# End of If LastExitCode
                        If($LASTEXITCODE -ne 0){
                            Out-File -Append $LogFile -InputObject "**ERROR** Unable to retrieve a Backlog Count, SendingMember:$($SplitMember[0]), ReceivingMember:$($SplitMember[1]) **ERROR**`r`n`tCommand - $BacklogCommand" -Force
                            #Write-Warning 'Backlog - ERROR'
                            $Data = New-Object psobject
                            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReplication Group&nbsp' -Value $NetRepGroupName
                            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspFolder Name&nbsp' -Value $Folder
                            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspSending Member&nbsp' -Value $($SplitMember[0])
                            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReceiving Member&nbsp' -Value $($SplitMember[1])
                            $Data | Add-Member -MemberType "noteproperty" -Name '&nbspBack Log Count&nbsp' -Value '**ERROR**'
                            $Global:OutPut += $Data
                        }# End of $LastExitCode 'Backlog'
                        Foreach ($BackLog in $BackLogCount){
                            $SplitBackLog = $BackLog -split ' {1,}'
                            $Array = Get-Content $LogFile
                            $Array[-1] = $Array[-1] += " - $($SplitBackLog[-1])"
                            Out-File $LogFile -InputObject $Array
                            Out-File -Append $LogFile -InputObject "`t`t`tCommand - $BacklogCommand" -Force
                            If ([int]$SplitBackLog[-1] -gt 75){
                                $Data = New-Object psobject
                                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReplication Group&nbsp' -Value $NetRepgroupName
                                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspFolder Name&nbsp' -Value $Folder
                                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspSending Member&nbsp' -Value $($SplitMember[0])
                                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReceiving Member&nbsp' -Value $($SplitMember[1])
                                $Data | Add-Member -MemberType "noteproperty" -Name '&nbspBack Log Count&nbsp' -Value $($SplitBackLog[-1])
                                $Global:OutPut += $Data
                            }# End of If Backlog
                        }# End of Foreach Backlog
            }# End of Foreach Member
        }# End of Foreach Folder
    }# End fo Foreach Rep Group
}# End of Foreach Domain
If ($Global:OutPut.Count -eq 0){
    $Data = New-Object psobject
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReplication Group&nbsp' -Value 'Nothing'
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspFolder Name&nbsp' -Value 'to'
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspSending Member&nbsp' -Value 'report'
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspReceiving Member&nbsp' -Value ''
    $Data | Add-Member -MemberType "noteproperty" -Name '&nbspBack Log Count&nbsp' -Value ':-)'
    $Global:OutPut += $Data}
Send-MailMessage -to $To -from $From -Subject $Subject -BodyAsHtml -Body ($Global:OutPut | ConvertTo-Html -head $a -body "<H2>DFSr Backlog Count - Greater than 75 files</H2>" -PostContent "<br><br>Detailed Log - $($LogFile.Replace('C:\',"\\$(get-content env:computername)\$($LogFile.substring(0,1))$\"))" | Out-String) -SmtpServer $MailServer