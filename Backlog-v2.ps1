$File_Path = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
If (-Not(Test-Path "$File_Path\Logs")){New-Item "$File_Path\Logs" -ItemType Directory}
$LogFile = "$File_Path\Logs\$(Get-Date -format yyyy-MM-dd)-Backlog.csv"
Get-ChildItem -Path "$File_Path\Logs" | Where-Object {$_.PSisContainer -eq $false -and $_.LastWriteTime -lt (Get-date).AddDays(-183)} | Remove-Item -Force
[int]$BacklogThreshold = '75'
#-----------------------------------------------------------------------
$To = 'Email@SomeWhere.com'
$From = 'Email@SomeWhere.com'
$Subject = "DFSr Backlog Counts - $((get-date).ToString('MM/dd/yyyy'))"
$MailServer = 'mail.SomeWhere.com'
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
$Style = '<style>'
$Style = $Style + 'TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}'
$Style = $Style + 'TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:DarkGray;text-align:center}'
$Style = $Style + 'TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;text-align:center}'
$Style = $Style + '</style>'
#-----------------------------------------------------------------------
$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$JobCount = 0
$Domains = 'Domain1','Domain2'
$Output = @()
$EmailBody = @()
$ProcessedJobCount = 0
Function Get-RepGroups {Param($Domain)
    $RepGroupCommand = "Dfsradmin rg list /Domain:'" + $Domain + "' /attr:rgname /csv"
    Invoke-Expression -Command $RepGroupCommand | Where-Object {-not($_ -like 'RgName' -or $_ -like '' -or $_ -like 'Domain System Volume')}
    #Invoke-Expression -Command $RepGroupCommand | Where-Object {$_ -like 'A*'}
}
Function Get-Members {Param($Domain,$RepGroupName)
    $MembersCommand = "DfsrAdmin Conn list /Domain:'" + $Domain + "' /RgName:'" + $RepGroupName + "' '/attr:SendMem,RecvMem' /csv"
    Invoke-Expression -Command $MembersCommand | Where-Object {-not($_ -like 'Sendmem*RecvMem' -or $_ -like '')}
}
Function Get-Folders {Param($Domain,$RepGroupName)
    $FolderListCommand = "DfsrAdmin RF List /Domain:'" + $Domain + "' /RgName:'" + $RepGroupName + "' /attr:RfName /csv"
    Invoke-Expression -Command $FolderListCommand | Where-Object {-not($_ -like 'RfName' -or $_ -like '')}
}
Function Que-Job {Param($Member,$RepGroupName,$ReplicatedFolder,$RetryCount=0)
    [string]$BacklogCommand = "DfsrDiag Backlog /SendingMember:'" + $($Member.Split(',')[0]) + "' /ReceivingMember:'" + $($Member.Split(',')[1]) + "' /RgName:'" + $RepGroupName + "' /RFName:'" + $ReplicatedFolder + "'"
    $Global:JobCount++
    $Global:JobsCreated += "$Domain#$RepGroupName#$ReplicatedFolder#$($Member.Split(',')[0])#$($Member.Split(',')[1])#$($RetryCount)"
    while (@(Get-Job -State Running).Count -ge 100) {Start-Sleep -Seconds 2}
    Start-Job -Name "$Domain#$RepGroupName#$ReplicatedFolder#$($Member.Split(',')[0])#$($Member.Split(',')[1])#$($RetryCount)" -ScriptBlock {param($BacklogCommand)
        Invoke-Expression -Command $BacklogCommand
    } -ArgumentList $BacklogCommand | Out-Null
}
Function Gather-Jobs{
    Get-Job | Foreach {
    $GatherWorkingJob = $_
    $JobsProcessed += $GatherWorkingJob.Name
    $GatherReceivedJob = Receive-Job $GatherWorkingJob.Id -Keep | Where-Object {$_ -like '*Backlog File Count:*' -or $_ -like '*Operation Failed*' -or $_ -like ''}
    If($GatherReceivedJob -like '*Operation Failed*'){
        If($([int]($GatherWorkingJob.name).Split('#')[-1]) -ne 10){
            $Retry = [int](($GatherWorkingJob.name).Split('#')[-1])+1
            $Global:ReRanJobCount++
            Que-Job -Member "$(($GatherWorkingJob.name).Split('#')[3]),$(($GatherWorkingJob.name).Split('#')[4])" -RepGroupName $(($GatherWorkingJob.name).Split('#')[1]) -ReplicatedFolder $(($GatherWorkingJob.name).Split('#')[2]) -RetryCount $Retry
            Remove-Job $GatherWorkingJob.Id -ErrorAction SilentlyContinue
        }
    }
}
}
Function Process-Jobs {
    Get-Job | Foreach {
        $ProcessWorkingJob = $_
        $Global:JobsProcessed += $ProcessWorkingJob.Name
        $ProcessReceivedJob = Receive-Job $ProcessWorkingJob.Id | Where-Object {$_ -like '*Backlog File Count:*' -or $_ -like '*Operation Failed*'}
        $Backlog = $Null
        $Global:ProcessedJobCount++
        If($ProcessReceivedJob -like '*Operation Failed*'){$ProcessBacklog = '**ERROR**'}
        Else{$ProcessBacklog = If($ProcessReceivedJob -ne $Null){$($ProcessReceivedJob -split ' {1,}')[-1]}Else{'0'}}
        If($ProcessBacklog -eq '**ERROR**' -or [int]$ProcessBacklog -ge $BacklogThreshold){$CommandRan = "DfsrDiag Backlog /SendingMember:'" + $(($ProcessWorkingJob.name).Split('#')[3]) + "' /ReceivingMember:'" + $(($ProcessWorkingJob.name).Split('#')[4]) + "' /RgName:'" + $(($ProcessWorkingJob.name).Split('#')[1]) + "' /RFName:'" + $(($ProcessWorkingJob.name).Split('#')[2]) + "'"}Else{$CommandRan = ''}
            $Global:Output += [PSCustomObject] @{
	        'Domain' = $((($ProcessWorkingJob.name).Split('#')).Split('.')[0])
	        'Rep Group' = $(($ProcessWorkingJob.name).Split('#')[1])
	        'Replicated Folder' = $(($ProcessWorkingJob.name).Split('#')[2])
            'Sending Member' = $(($ProcessWorkingJob.name).Split('#')[3])
            'Receiving Member' = $(($ProcessWorkingJob.name).Split('#')[4])
            'BackLog' = $ProcessBacklog
            'Command' = $CommandRan
        }
        If(($ProcessReceivedJob -ne $Null) -and ($ProcessBacklog -eq '**ERROR**' -or [int]$ProcessBacklog -ge $BacklogThreshold)){
            $Global:EmailBody += [PSCustomObject] @{
	        'Domain' = $((($ProcessWorkingJob.name).Split('#')).Split('.')[0])
	        'Rep Group' = $(($ProcessWorkingJob.name).Split('#')[1])
	        'Replicated Folder' = $(($ProcessWorkingJob.name).Split('#')[2])
            'Sending Member' = $(($ProcessWorkingJob.name).Split('#')[3])
            'Receiving Member' = $(($ProcessWorkingJob.name).Split('#')[4])
            'BackLog' = $ProcessBacklog
            }
        }
    }
    Remove-Job $ProcessWorkingJob.Id -ErrorAction SilentlyContinue
}

Foreach ($Domain in $Domains) {
Get-RepGroups -Domain $Domain | Foreach {
    $RepGroupName = $_
    $Members = Get-Members -Domain $Domain -RepGroupName $RepGroupName
    Get-Folders -Domain $Domain -RepGroupName $RepGroupName | Foreach {
        Foreach ($Member in $Members){
            Que-Job -Member $Member -RepGroupName $RepGroupName -ReplicatedFolder $_
            }
    }
}#$NetRepGroupNames | Foreach {
}#Foreach ($Domain in $Domains){
while($val -ne 10){
    $val++
    Get-Job | Wait-Job -Timeout 5400 | Out-Null
    Gather-Jobs
}
Get-Job | Wait-Job -Timeout 5400 | Out-Null
Process-Jobs
$Output | Sort-Object 'Rep Group','Replicated Folder','Sending Member' | Export-Csv $LogFile -NoTypeInformation
If ($EmailBody -notlike ''){Send-MailMessage -To $To -Subject $Subject -From $From -BodyAsHtml -Body ($EmailBody | ConvertTo-Html -head $Style -body "<H2>DFSr Backlog Counts Greater than $BacklogThreshold.</H2>Jobs Ran = $($Global:JobCount - $Global:ReRanJobCount), Jobs Processed = $Global:ProcessedJobCount <br><br>" -PostContent "<br><br>Detailed Log - $($LogFile.Replace('C:\',"\\$(get-content env:computername)\$($LogFile.substring(0,1))$\"))<br><br>Total Elapsed Time: $($elapsed.Elapsed.ToString())" | Out-String) -SmtpServer $MailServer}
Else{Send-MailMessage -To $To -Subject $Subject -From $From -BodyAsHtml -Body (ConvertTo-Html -body "<H2>DFSr Backlog Counts Greater than $BacklogThreshold.</H2>Jobs Ran = $($Global:JobCount - $Global:ReRanJobCount), Jobs Processed = $Global:ProcessedJobCount<br><br><font size=6 color=Green>Nothing to Report</font>" -PostContent "<br><br>Detailed Log - $($LogFile.Replace('C:\',"\\$(get-content env:computername)\$($LogFile.substring(0,1))$\"))<br><br>Total Elapsed Time: $($elapsed.Elapsed.ToString())" | Out-String) -SmtpServer $MailServer}