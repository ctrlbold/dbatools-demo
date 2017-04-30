# Don't run everything, thanks @alexandair!
break

# IF THIS SCRIPT IS RUN ON LOCAL SQL INSTANCES, YOU MUST RUN ISE OR POWERSHELL AS ADMIN
# Otherwise, a bunch of commands won't work.
cls

# Paths that auto-load modules
$env:PSModulePath -Split ";"

# This is the [development] aka beta branch
Import-Module C:\github\dbatools -Force

# Set some vars
$new = "localhost\sql2016"
$old = $instance = "localhost"
$allservers = $old, $new

#region backuprestore

Start-Process https://dbatools.io/snowball

# standard
Restore-DbaDatabase -SqlInstance localhost -Path "C:\temp\AdventureWorks2012-Full Database Backup.bak"
Restore-DbaDatabase -SqlInstance localhost -Path "C:\temp\AdventureWorks2012-Full Database Backup.bak" -WithReplace

# ola!
Invoke-Item \\workstation\backups\WORKSTATION\SharePoint_Config
Restore-DbaDatabase -SqlInstance $new -Path \\workstation\backups\WORKSTATION\SharePoint_Config -WithReplace -DestinationDataDirectory C:\temp

foreach ($database in (Get-ChildItem -Directory \\workstation\backups\sql2012).FullName)
{
  Write-Output "Processing $database"
  Restore-DbaDatabase -SqlInstance localhost\sql2016 -Path $database -NoRecovery -RestoreTime (Get-date).AddHours(-3)
}

# What about backups?
Get-DbaDatabase -SqlInstance localhost -Databases SharePoint_Config | Backup-DbaDatabase -BackupDirectory C:\temp -NoCopyOnly

# history
Get-DbaBackupHistory -SqlInstance localhost -Databases AdventureWorks2012, SharePoint_Config | Out-GridView

# backup header
Read-DbaBackupHeader -SqlInstance $instance -Path "\\workstation\backups\WORKSTATION\SharePoint_Config\FULL\WORKSTATION_SharePoint_Config_FULL_20170114_224317.bak"
Read-DbaBackupHeader -SqlInstance $instance -Path "\\workstation\backups\WORKSTATION\SharePoint_Config\FULL\WORKSTATION_SharePoint_Config_FULL_20170114_224317.bak" | SELECT ServerName, DatabaseName, UserName, BackupFinishDate, SqlVersion, BackupSizeMB

# Find it!
Find-DbaCommand -Tag Config

#endregion

#region SPN
Start-Process https://dbatools.io/schwifty
Start-Process "C:\Program Files\Microsoft\Kerberos Configuration Manager for SQL Server\KerberosConfigMgr.exe"

# oh this is tough - no domain
Get-DbaSpn | Format-Table
$allservers | Test-DbaSpn | Out-GridView -PassThru | Set-DbaSpn -Whatif
Get-DbaSpn | Remove-DbaSpn -Whatif

#endregion

#region holiday
# Get-DbaLastBackup - by @powerdbaklaas
$allservers | Get-DbaLastBackup | Out-GridView
$allservers | Get-DbaLastBackup | Where-Object LastFullBackup -eq $null | Format-Table -AutoSize
$allservers | Get-DbaLastBackup | Where-Object { $_.SinceLog -gt '00:15:00' -and $_.RecoveryModel -ne 'Simple' -and $_.Database -ne 'model' } | Select Server, Database, SinceFull, DatabaseCreated | Out-GridView

# LastGoodCheckDb - by @jagoop
$checkdbs = Get-DbaLastGoodCheckDb -SqlInstance $instance
$checkdbs
$checkdbs | Where LastGoodCheckDb -eq $null
$checkdbs | Where LastGoodCheckDb -lt (Get-Date).AddDays(-1)

# Disk Space - by a bunch of us
Get-DbaDiskSpace -SqlInstance $allservers
$diskspace = Get-DbaDiskSpace -SqlInstance $allservers -Detailed
$diskspace | Where PercentFree -lt 20

#endregion

#region testing backups

# Did you see? SqlServer module is now in the Powershell Gallery too!
Get-Help Test-DbaLastBackup -Online
Import-Module SqlServer
Invoke-Item (Get-Item SQLSERVER:\SQL\LOCALHOST\DEFAULT).DefaultFile

Test-DbaLastBackup -SqlInstance localhost | Out-GridView
Test-DbaLastBackup -SqlInstance localhost -Destination localhost\sql2016 -VerifyOnly | Out-GridView

#endregion

#region VLFs

$allservers | Test-DbaVirtualLogFile | Where-Object {$_.Count -ge 50} | Sort-Object Count -Descending | Out-GridView

#endregion

#region databasespace

# Get Db Free Space AND write it to disk
Get-DbaDatabaseFreespace -SqlInstance $instance
Get-DbaDatabaseFreespace -SqlInstance $instance -IncludeSystemDBs | Out-DbaDataTable | Write-DbaDataTable -SqlInstance $instance -Table tempdb.dbo.DiskSpaceExample
Get-DbaDatabaseFreespace -SqlInstance $instance -IncludeSystemDBs | Out-DbaDataTable | Write-DbaDataTable -SqlInstance $instance -Database tempdb -Table DiskSpaceExample -AutoCreateTable

# Run a lil query
Ssms.exe "C:\temp\tempdbquery.sql"

#endregion

#region blog posts turned commands

# Test/Set SQL max memory
$allservers | Get-DbaMaxMemory
$allservers | Test-DbaMaxMemory | Format-Table
$allservers | Test-DbaMaxMemory | Where-Object { $_.SqlMaxMB -gt $_.TotalMB } | Set-DbaMaxMemory -WhatIf
Set-DbaMaxMemory -SqlInstance $instance -MaxMb 2048

# RecoveryModel
Test-DbaFullRecoveryModel -SqlInstance localhost
Test-DbaFullRecoveryModel -SqlInstance localhost | Where { $_.ConfiguredRecoveryModel -ne $_.ActualRecoveryModel }

# Backup History!
Get-DbaBackupHistory -SqlInstance $instance
Get-DbaBackupHistory -SqlInstance $instance | Out-GridView
Get-DbaBackupHistory -SqlInstance $instance -Databases AdventureWorks2012 | Format-Table -AutoSize

# Restore History!
Get-DbaRestoreHistory -SqlInstance $instance | Out-GridView
 
#endregion

#region mindblown

# Find-DbaStoredProcdure - @claudioessilva, @cl, Stephen Bennett
# 37,545 SQL Server stored procedures on 9 servers evaluated in 8.67 seconds!

$allservers | Find-DbaStoredProcedure -Pattern dbatools
$allservers | Find-DbaStoredProcedure -Pattern dbatools | Select * | Out-GridView
$allservers | Find-DbaStoredProcedure -Pattern '\w+@\w+\.\w+'

# Remove dat orphan - by @sqlstad
Find-DbaOrphanedFile -SqlInstance $instance
((Find-DbaOrphanedFile -SqlInstance $instance -RemoteOnly | Get-ChildItem | Select -ExpandProperty Length | Measure-Object -Sum)).Sum / 1MB
Find-DbaOrphanedFile -SqlInstance $instance -RemoteOnly | Remove-Item

# Reset-SqlAdmin
Reset-SqlAdmin -SqlInstance $instance -Login sqladmin

#endregion

#region bits and bobs

# DbaStartupParameter
Get-DbaStartupParameter -SqlInstance $instance
Get-DbaStartupParameter -SqlInstance $new

# sp_whoisactive
Invoke-DbaWhoisActive -SqlInstance $instance -ShowOwnSpid -ShowSystemSpids
Install-DbaWhoIsActive -SqlInstance localhost -Database master
Invoke-DbaWhoisActive -SqlInstance $instance -ShowOwnSpid -ShowSystemSpid
Invoke-DbaWhoisActive -SqlInstance $instance -ShowOwnSpid -ShowSystemSpid | Out-GridView

#endregion

#region configs

# Get-DbaSpConfigure - @sirsql
$oldprops = Get-DbaSpConfigure -SqlInstance $old
$newprops = Get-DbaSpConfigure -SqlInstance $new

$propcompare = foreach ($prop in $oldprops) {
  [pscustomobject]@{
  Config = $prop.DisplayName
  'SQL Server 2014' = $prop.RunningValue
  'SQL Server 2016' = $newprops | Where ConfigName -eq $prop.ConfigName | Select -ExpandProperty RunningValue
  }
} 

$propcompare | Out-GridView

# Copy-SqlSpConfigure
Copy-SqlSpConfigure -Source $old -Destination $new -Configs DefaultBackupCompression, IsSqlClrEnabled

# Get-DbaSpConfigure - @sirsql
Get-DbaSpConfigure -SqlInstance $new | Where-Object { $_.ConfigName -in 'DefaultBackupCompression', 'IsSqlClrEnabled' } | 
Select-Object ConfigName, RunningValue, IsRunningDefaultValue | Format-Table -AutoSize

#endregion