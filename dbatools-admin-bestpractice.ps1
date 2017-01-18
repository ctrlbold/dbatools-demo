﻿# IF THIS SCRIPT IS RUN ON LOCAL SQL INSTANCES, YOU MUST RUN ISE OR POWERSHELL AS ADMIN
# Otherwise, a bunch of commands won't work.

# Paths that auto-load modules
$env:PSModulePath -Split ";"

# This is the [development] aka beta branch
Import-Module C:\github\dbatools -Force

# Set some vars
$new = "localhost\sql2016"
$old = $instance = "localhost"
$allservers = "localhost","localhost\sql2016"

# Get-DbaSpConfigure - @sirsql
$oldprops = Get-DbaSpConfigure -SqlServer localhost
$newprops = Get-DbaSpConfigure -SqlServer localhost\sql2016

$propcompare = foreach ($prop in $oldprops) {
    [pscustomobject]@{
    Config = $prop.DisplayName
    'SQL Server 2012' = $prop.RunningValue
    'SQL Server 2016' = $newprops | Where ConfigName -eq $prop.ConfigName | Select -ExpandProperty RunningValue
    }
} 

$propcompare | Out-GridView

# Copy-SqlSpConfigure
Copy-SqlSpConfigure -Source $old -Destination $new -Configs DefaultBackupCompression, IsSqlClrEnabled

#Copy-SqlSpConfigure -Source localhost -conf

# Get-DbaSpConfigure - @sirsql
Get-DbaSpConfigure -SqlServer $old | Where-Object { $_.ConfigName -in 'DefaultBackupCompression', 'IsSqlClrEnabled' }


# Get-DbaLastBackup - by @powerdbaklaas
$allservers | Get-DbaLastBackup
$allservers | Get-DbaLastBackup | Where-Object LastFullBackup -eq $null | Format-Table -AutoSize
$allservers | Get-DbaLastBackup | Where-Object { $_.LastLogBackup -eq $null -and $_.RecoveryModel -ne 'Simple' -and $_.Database -ne 'model' } | Format-Table -AutoSize
$allservers | Get-DbaLastBackup | Where-Object { $_.SinceLog -gt '00:15:00' -and $_.RecoveryModel -ne 'Simple' -and $_.Database -ne 'model' } | Format-Table -AutoSize

# LastGoodCheckDb - by @jagoop
$checkdbs = Get-DbaLastGoodCheckDb -SqlServer $instance
$checkdbs
$checkdbs | Where LastGoodCheckDb -lt (Get-Date).AddDays(-1)

# Disk Space - by a bunch of us
Get-DbaDiskSpace -SqlInstance $allservers
$diskspace = Get-DbaDiskSpace -SqlInstance $allservers -Detailed
$diskspace  | Where PercentFree -lt 20 

# Test last backup
Get-Help Test-DbaLastBackup -Online
Invoke-Item (Get-Item SQLSERVER:\SQL\LOCALHOST\DEFAULT).DefaultFile

Test-DbaLastBackup -SqlServer $instance 
Test-DbaLastBackup -SqlServer $instance -Destination $new -MaxMb 10
Test-DbaLastBackup -SqlServer $instance -Destination $new -VerifyOnly | Out-GridView

Start-Process https://youtu.be/Ah0jabU9G8o?t=2m56s

# Test/Repair
Test-DbaServerName -SqlServer $allservers
Repair-DbaServerName -SqlServer $allservers

# One of my favs! - by @sqldbawithbeard
Get-Help Remove-SqlDatabaseSafely -Online
Remove-SqlDatabaseSafely -SqlServer $instance -Databases AdventureWorks2008R2 -BackupFolder \\workstation\migration

# Get and Set SqlTempDbConfiguration - by @mike_fal
Get-Help Test-SqlTempDbConfiguration -Online
Test-SqlTempDbConfiguration -SqlServer $instance
Set-SqlTempDbConfiguration -SqlServer $instance -DataFileSizeMb 2048

# Test-DbaPowerPlan
Invoke-Item C:\github\TrainingMaterial\Videos\Test-DbaPowerPlan.mp4

# Get/Set SQL max memory
Test-DbaMaxMemory -SqlServer $allservers 
Test-DbaMaxMemory -SqlServer $allservers | Set-DbaMaxMemory
Test-DbaMaxMemory -SqlServer $allservers | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory
Set-DbaMaxMemory -SqlServer $instance -MaxMb 2048

# sp_whoisactive
Show-SqlWhoisActive -SqlServer $instance -ShowOwnSpid -ShowSystemSpids

# Awesome!
Reset-SqlAdmin -SqlServer $instance -Login sqladmin

# Now
Test-DbaFullRecoveryModel -SqlServer $instance
Test-DbaFullRecoveryModel -SqlServer $instance | Where { $_.ConfiguredRecoveryModel -ne $_.ActualRecoveryModel }

# Test-VirtualLog file
$allservers | Test-DbaVirtualLogFile
$bigvlfs = $allservers | Test-DbaVirtualLogFile | Where-Object {$_.Count -ge 50} | Sort-Object Count -Descending
$bigvlfs

$database = ($bigvlfs | Select -Last 1).Database

# Virtual Log files
Expand-SqlTLogResponsibly -SqlServer $instance -Databases $database -TargetLogSizeMB 16 -IncrementSizeMB 1 -ShrinkLogFile -ShrinkSizeMB 1 
Test-DbaVirtualLogFile -SqlServer $instance -Databases $database

# backup header
Read-DbaBackupHeader -SqlServer $instance -Path C:\migration\SQL2012\WSS_Content\FULL\SQL2012_WSS_Content_FULL_20161218_113644.bak
Read-DbaBackupHeader -SqlServer $instance -Path C:\migration\SQL2012\WSS_Content\FULL\SQL2012_WSS_Content_FULL_20161218_113644.bak | 
SELECT ServerName, DatabaseName, UserName, BackupFinishDate, SqlVersion, BackupSizeMB

Read-DbaBackupHeader -SqlServer $instance -Path C:\migration\SQL2012\WSS_Content\FULL\SQL2012_WSS_Content_FULL_20161218_113644.bak -FileList  | Out-GridView

# Remove dat orphan - by @sqlstad
Find-DbaOrphanedFile -SqlServer $instance
((Find-DbaOrphanedFile -SqlServer $instance -LocalOnly | Get-ChildItem | Select -ExpandProperty Length | Measure-Object -Sum)).Sum / 1MB
Find-DbaOrphanedFile -SqlServer $instance -LocalOnly | Remove-Item

# Backup History!
Get-DbaBackupHistory -SqlServer $instance
Get-DbaBackupHistory -SqlServer $instance | Out-GridView
Get-DbaBackupHistory -SqlServer $instance -Databases AdventureWorks2012 | Format-Table -AutoSize

# Restore History!
Get-DbaRestoreHistory -SqlServer $instance | Out-GridView

# DbaStartupParameter
Get-DbaStartupParameter -SqlServer $instance
Get-DbaStartupParameter -SqlServer $new

# Resolve things
Resolve-DbaNetworkName -ComputerName $instance
Resolve-DbaNetworkName -ComputerName $env:computername

# Test Db compat
Test-DbaDatabaseCompatibility -SqlServer $instance -Detailed | Format-Table -AutoSize

# Test Db collation
Test-DbaDatabaseCollation -SqlServer $instance -Detailed | Format-Table -AutoSize
 
# Get Db Free Space AND write it to disk
Get-DbaDatabaseFreespace -SqlServer $instance
Get-DbaDatabaseFreespace -SqlServer $instance -IncludeSystemDBs | Out-DbaDataTable | Write-DbaDataTable -SqlServer $instance -Table tempdb.dbo.DiskSpaceExample
Get-DbaDatabaseFreespace -SqlServer $instance -IncludeSystemDBs | Out-DbaDataTable | Write-DbaDataTable -SqlServer $instance -Table tempdb.dbo.DiskSpaceExample -AutoCreateTable

# Run a lil query
Ssms.exe "C:\temp\tempdbquery.sql"

<# Good ol Phil #>

$login = "WORKSTATION\phil"

Add-SqlLogin -ServerInstance $instance -LoginName $login -LoginType WindowsUser
Set-DbaDatabaseOwner -SqlServer $instance -Databases WSS_Logging, AdventureWorks2012 -TargetLogin $login
Set-DbaJobOwner -SqlServer $instance -Jobs 'Backup - Full - User','Backup - Full - System' -TargetLogin $login

Remove-SqlLogin -ServerInstance $instance  -LoginName $login -RemoveAssociatedUsers

Set-DbaDatabaseOwner -SqlServer $instance -Databases WSS_Logging, AdventureWorks2012 -TargetLogin sa
Set-DbaJobOwner -SqlServer $instance -Jobs 'Backup - Full - User','Backup - Full - System' -TargetLogin sa

Remove-SqlLogin -ServerInstance $instance -LoginName $login -RemoveAssociatedUsers

<#Party-Parrot#>

Get-Command *Orphan*
Copy-SqlDatabase -Source $old -Destination $new -DetachAttach -Reattach -Databases WSS_Logging -Force
Repair-SqlOrphanUser -SqlServer $new