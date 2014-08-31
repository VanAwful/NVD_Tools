#NVD Create Database
#Created 7/18/2014
#brinkn@nationwide.com

#Used to create a database to but NVD data into
#Relies on Powershell CVE from 
#http://psqlite.codeplex.com/wikipage?title=Creating%20Tables&referringTitle=Documentation

##NOTE:  Do to issues with files with brackets[] in the name.  Please dont load a file with brackets

##TODO
#Figure a way to deal with the bracket problem in file names

##Inputs
[CmdletBinding(DefaultParametersetName="Create")]
[CmdletBinding()]
param(	[switch]$help,
		[string]$DatabaseFile,		#The default name to use
		[string]$scriptpath = $MyInvocation.MyCommand.Path, 	#The directory to store files
		[switch]$Clean = $false,									#If true, drop and recreate tables
		[switch]$Access = $false									#If true, create an access database
	)


##Load Assemblies
[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
import-module SQLite 	#http://psqlite.codeplex.com/

##Variables
$Filter = 'All Files|*.*'

##Functions
function Write-HelpMessage(){
	$USAGE='SQLite Database Create Tool
Created by brinkn@nationwide.com

	Parameters:             
	-Help                          (This Message)
	-Database	   <FILENAME>      (Name of Database to create)
	-Clean						   (Drop all tables and recreate)
	-Access						   (Create an Access MDB file instead of SQLite)

	        '
	Write-host $usage
}
Function FileExists {
	Param(
		[string]$FileName="")  #Name of file to check
	Write-Verbose "Checking for existance of $FileName"
	$result = Test-Path -path $FileName 
	if ($result){Write-Verbose "The file $FileName exists."}else{Write-Verbose "The file $FileName does not exist."}
	return $result
}
Function GetFileLocation($StartDirectory, $Filter){
	#Powershell tip of the day
	#http://s1403.t.en25.com/e/es.aspx?s=1403&e=85122&elq=7b9bf21b612743dea14c73c513d956f9
	$dialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog

	$dialog.AddExtension = $true
	$dialog.Filter = $filter
	$dialog.Multiselect = $false
	$dialog.FilterIndex = 0
	$dialog.InitialDirectory = $StartDirectory
	$dialog.RestoreDirectory = $true
	#$dialog.ShowReadOnly = $true
	$dialog.ReadOnlyChecked = $false
	$dialog.Title = 'Select a Database File'
	$dialog.checkfileexists = $false

	$result = $dialog.ShowDialog()
	if ($result = 'OK')
	{
	    $filename = $dialog.FileName
	    $readonly = $dialog.ReadOnlyChecked
	    if ($readonly) { $mode = 'read-only' } else {$mode = 'read-write' }
		return $filename
	} else {return "cancel"} 
}
Function Create-DataBase($Db){
 	$application = New-Object -ComObject 'ADOX.Catalog'
	$application.Create("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$db")
} #End Create-DataBase
Function Invoke-ADOCommand($Db, $Command){
 $connection = New-Object System.Data.OleDb.OleDbConnection("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$Db")
 $connection.Open()
 $cmd = New-Object System.Data.OleDb.OleDbCommand($Command, $connection) 
 $cmd.ExecuteNonQuery() 
} #End Invoke-ADOCommand

##Begin Program
Write-Host "NVD SQLite Database Creator .01"

##Parameter Checking
#Check if help message was requested
if ($help) {Write-HelpMessage;break}

#Start Metrics
$sw = [Diagnostics.Stopwatch]::StartNew()

if ($DatabaseFile.length -le 1) {
	#Since there was not a policy provided on the command line, go ahead and ask for one.
	$scriptpath = $MyInvocation.MyCommand.Path
	$scriptpath = Split-Path $scriptpath
	$DatabaseFile = GetFileLocation $scriptpath $filter 	#file with policy information
	if ($DatabaseFile -eq "cancel"){exit}	#On cancel, exit
}
#We need to modify the $FileList string because of the way powershell handles [] square brackets.
#Note this does not actually work, and should be avoided
#$databaseFile = $databaseFile.Replace('[', '``[').Replace(']', '``]')
#$databaseFile = Resolve-Path $databaseFile #File the full path and ensure if a ..\ is provide we get the right file
Write-Verbose "Database file: $databaseFile"
Write-Verbose "Clean Flag: $Clean"

# Check if file exists, if not error out.
if((fileexists($databaseFile)) -AND (!($Clean))){Write-Host "The file: $databaseFile exists.  To recreate add the Clean flag";break}

$strCVETable =  "[cve_id] TEXT PRIMARY KEY NOT NULL UNIQUE,
		published TEXT,
		modified TEXT,
		summary TEXT,
		score TEXT,
		severity TEXT,
		vector TEXT,
		complexity TEXT,
		authentication TEXT,
		confidentiality TEXT,
		integrity TEXT,
		availability TEXT,
		cwe TEXT" 
$strApplicationTable = "cpe TEXT,
		cve_id TEXT"
$strReferenceTable = "cve_id TEXT,
		type TEXT,
		source TEXT,
		reference TEXT"	
$strCPETable = "cpe TEXT PRIMARY KEY NOT NULL UNIQUE,
		title TEXT,
		reference TEXT,
		cpe23 TEXT"

if($Access) { 
	write-host "This will be an access database"
	if($Clean){
		Write-Verbose "Attempting to remove tables"
	Invoke-ADOCommand -db $DatabaseFile -command "DROP Table CVE"
	Invoke-ADOCommand -db $DatabaseFile -command "DROP Table Application"
	Invoke-ADOCommand -db $DatabaseFile -command "DROP Table CPE"
	Invoke-ADOCommand -db $DatabaseFile -command "DROP Table Reference"
	} else {
		Create-DataBase -db $DatabaseFile
		$table = "CVE" 
	}
	$command = "Create Table CVE `($strCVETable`)"
	Invoke-ADOCommand -db $DatabaseFile -command $command
	$command = "Create Table Application `($strApplicationTable`)"
	Invoke-ADOCommand -db $DatabaseFile -command $command
	$command = "Create Table CPE `($strCPETable`)"
	Invoke-ADOCommand -db $DatabaseFile -command $command
	$command = "Create Table Reference `($strReferenceTable`)"
	Invoke-ADOCommand -db $DatabaseFile -command $command		

} else {
	#attempt to create a NVDDB Database
	mount-sqlite -name NVDDB -dataSource $DatabaseFile |Out-Null

	if($Clean){
	Write-Verbose "Attempting to remove tables"
		Remove-Item -Path NVDDB:/CVE |Out-Null
		Remove-Item -Path NVDDB:/Application |Out-Null
		Remove-Item -Path NVDDB:/CPE |Out-Null
	}

	#Load the Schema for CVE
	Write-Verbose "Creating CVE table"
	new-item -path NVDDB:/CVE -value  $strCVETable |Out-Null

	#Load the Schema for CVE - CPE
	#Applications with CVE NVDDB
	Write-Verbose "Creating Application table"
	new-item -path NVDDB:/Application -value $strApplicationTable |Out-Null

	#Load the Schema for CPE - which are all known applications
	#Common Platform Enumeration (CPE) Dictionary
	#http://nvd.nist.gov/cpe.cfm
	Write-Verbose "Creating CPE table"
	new-item -path NVDDB:/CPE -value $strCPETable |Out-Null
	
	#Load the Schema for References - Which contains links to vendor advisories
	Write-Verbose "Creating References table"
	new-item -path NVDDB:/Reference -value $strReferenceTable |Out-Null
	#All done end our connection
	Write-Verbose "Closing connection"
	Remove-PSDrive NVDDB
}
#Print Metrics
$sw.Stop()
Write-Host "Complete!"
write-verbose "Time Elapsed: $($sw.Elapsed)"