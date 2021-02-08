#!/usr/bin/perl

# ++
# File:     		db-server-checks.pl
# Created:  		19-Aug-2020, by Andy
# Reason:   		For the db tools. Check specified server settings. 
# --
# Abstract: 		Can be invoked directly, but the expectation is to be called by the driver script. The driver script will determine if Operations Bridge
#					components are already installed or not, allowing information to be read from the configuration if necessary
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	18-Aug-2020	Created from POC script. Splitting functionality out - db checks and server checks done separately.
# --

use strict;
use warnings;

#
# To add the OpsB Common utilities need to add the directory to @INC
#

use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(abs_path $0) . '/lib'; # Utilies pm files below here
use OpsB::Common; # Holds a number of routines, most we will access with the full name but better top use the short name for some
use OpsB::Common qw(WO true false $IsWindows M_NONE M_INFO M_OK M_WARN M_ERROR M_FATAL M_DEBUG $ARG_Debug $ARG_Log $ARG_Color $ARG_Quiet $ARG_Timeout $ARG_NoWelcome $ARG_Help $MF_UTIL); 
use OpsB::Database;
use OpsB::Database qw(DATABASE_MODULE_VERSION $DBTYPE_MSSQL $DBTYPE_Oracle $DBTYPE_PG);

#
# required
#

our $scriptVersion = "2.2";
our $scriptArgs = "server,port,db,user,pwd,sid,trusted,set,trusted,size,dbtype,force,showok,frag";

#
# Script Specific Arguments
#

our $ARG_Server = "";
our $ARG_Port = "";
our $ARG_DB = "";
our $ARG_User = "";
our $ARG_PWD = "";
our $ARG_Trusted = false;
our $ARG_SID = "";
our $ARG_DBType = "";
our $ARG_Size = "";
our $ARG_Set = false;
our $ARG_Force = false;
our $ARG_ShowOK = false;
our $ARG_Frag = 30;

#
# Additional
#

our $DBType_MSSQL_Input = OpsB::Database::DBTYPE_MSSQL_String;
$DBType_MSSQL_Input =~ s/ //g; # Do this to remove spaces from "MS SQL" to make the input easier - MSSQL

our $Size_Small = "Small";
our $Size_Medium = "Medium";
our $Size_Large = "Large";

our ($useSettings, $settingsData, $settingsError) = (false, "", "");
our $settingsFile = OpsB::Common::GetScriptDir($0) . "settings.dat";
if (-e $settingsFile) {($useSettings, $settingsData, $settingsError) = OpsB::Common::ReadFileToString($settingsFile);}

our $OBMVersion = "";

if ($useSettings == true) {
		my $line = OpsB::Common::FindLineWithKey($settingsData, "<VersionInfo OBM");
		$OBMVersion = OpsB::Common::GetAttributeFromData($line, "Version");
}

#
# For passing information in the hash to the "show" routines
#

our $TAG_Query = "*QUERY*";
our $TAG_ShowAll = "*SHOWALL*";

our $INFO_Only = "<Information Only>";

our %paramSetting = ();
our %updateParams = ();

our $FRAG_Warn = 10;
our $FRAG_Error = 20;

#
# Messages
#

our $MSG_DBType_Prompt = "Specify the Database Server Type (%s=%s, %s=%s, %s=%s)";
our $MSG_DBType_Invalid = sprintf("\tThe -dbtype %s is invalid, it must be a value between 1 and 3 or one of \"%s\", \"%s\" or \"%s\"", "%s", $DBType_MSSQL_Input, OpsB::Database::DBTYPE_Oracle_String, OpsB::Database::DBTYPE_PG_String);
our $MSG_TrustedOnlyWithSQL = sprintf("\tTrusted connection is only allowed with %s database type", OpsB::Database::DBTYPE_MSSQL_String);
our $MSG_TrustedOnlyOnWindows = "\tTrusted commection is only allowed when running the script on Windows";
our $MSG_NoUser = "\tNo user was provided for connecting to the server";
our $MSG_NoPWD = "\tNo password was provided for connecting to the server";
our $MSG_CheckingServer = "Checking %s server %s on port %s (connecting as user %s) ...";
our $MSG_TrustedUser = "<Windows Authentication>";
our $MSG_NoSID = "\tFor the Oracle Database type, the SID must be specified";
our $MSG_NoSettings = "The settings file \"$settingsFile\" could not be located, script cannot continue";
our $MSG_ServerVersion = "Database Server version: %s";
our $MSG_ServerNeedsUpdating = " - OBM Version %s requires %s Version %s (%s) or higher to be installed";
our $MSG_ServerFail = "Unable to continue with database server checks, verify that the specified %s server is available and that credentials are correct";
our $MSG_ServerVersionFriendly = "Server Version %s (%s)";
our $MSG_ServerSupported = " is supported by OBM Version %s";
our $MSG_InvalidSize = sprintf("\tAn invalid configuration size (%s) was specified. It must be one of \"%s\", \"%s\" or \"%s\"", "%s", $Size_Small, $Size_Medium, $Size_Large);
our $MSG_HowToSet = "Run the utility again with the \"-set\" switch in order to update these parameters, or work with the dba to make changes"; 
our $MSG_NoChanges = "No changes will be made"; 
our $MSG_WorkWithDBA = "Work with the %s dba to make the above changes to the server settings";
our $MSG_SettingsOK = "The current settings are appropriate for a %s configuration";
our $MSG_MakingChanges = "Making identified configuration changes to %s server...";
our $MSG_Set_Error = "There were errors executing the update - ensure that the account \"%s\" has sufficient rights to make server changes";
our $MSG_Reload = "Reloading updated parameters...";
our $MSG_ReloadFailed = "Unable to reload configuration";
our $MSG_ShowAfterUpdate = "Checking parameters after updates...";
our $MSG_PossibleRestart = "If any parameters show that a restart is required then %s needs to be restarted prior to them taking effect. Be sure to shut down OBM before doing this";
our $MSG_DBFileGettingFragmented = "Number of fragments needs to be monitored";
our $MSG_DBFileDeFrag = "The file should be defragmented";
our $MSG_DBFileMissing = "File not found on server";
our $MSG_DBFileRemote = "File is on remote host: %s";
our $MSG_DBFileError = "Error %s checking file";
our $MSG_DBFileOnSys = "File is on the System Disk";
our $MSG_DBFileAlsoOnSys = " and is on the System Disk";;

#
# As we use this in varios places, do at the start#
#
our ($My_Name, $My_OS, $My_Architecture, $My_OSVersion) = OpsB::Common::GetHostInfo();

#
# Main start point
#

sub Main() {
	my $msg = "";
	
	#
	# First get the inputs, then we can start debug logging
	#
	
	GetInputs();
	
	WO("Main: Start", M_DEBUG);
	
	#
	# Show the inputs  - set $argValues to the list from this sccript, the generic ones will be added in the common module. For example
	#
	# my $argValues = sprintf("\n\t-xyz = %s\n\t-abc = %s\n", $ARG_XYZ, $ARG_ABC);
	#
	
	my $argValues = "\n\t-server\t\t$ARG_Server\n\t-db\t\t\t$ARG_DB\n\t-Port\t\t$ARG_Port\n\t-User\t\t$ARG_User\n\t-sid\t\t\t$ARG_SID\n\t-dbtype\t\t$ARG_DBType\n\t-size\t\t$ARG_Size";	
	OpsB::Common::ShowInputs($argValues);
	
	#
	# Show banner
	#
	
	my $additionalModules = sprintf("DB Version: %s", DATABASE_MODULE_VERSION);
	my $description = "This script verifies a number of database servers settings. For Postgres, it can be used to make changes to the settings";
	OpsB::Common::SayHello($scriptVersion, $additionalModules, $description); # ScriptVersion, AdditionalModules, Specific Description 
	
	if ($ARG_Help == true) {
		#
		# Show help and stop
		#
		
		ShowHelp();
		return;
	}
	
	my ($argsOK, $argsError) = OpsB::Common::ValidateArgs($scriptArgs);
	
	if ($argsOK == false) {
		ShowHelp();
		$argsError = sprintf(OpsB::Common::MSG_BadArgs, $argsError);
		WO($argsError, M_FATAL);
		WO("");
		return;
	}
	
	my ($checkInputs, $inputsError) = CheckInputs();
	
	if ($checkInputs == false) {
		ShowHelp();
		$inputsError = sprintf(OpsB::Common::MSG_BadArgs, $inputsError);
		WO("");
		WO($inputsError, M_FATAL);
		WO("");
		return;
	}
	
	OpsB::Common::ShowInputs("\n\t-server\t\t$ARG_Server\n\t-db\t\t\t$ARG_DB\n\t-Port\t\t$ARG_Port\n\t-User\t\t$ARG_User\n\t-sid\t\t\t$ARG_SID\n\t-dbtype\t\t$ARG_DBType\n\t-size\t\t$ARG_Size");
	ContinueScript();
	
	if ($ARG_Log == true) {
		my $logFile = OpsB::Common::GetLogFileName();
		
		if (-e $logFile) {
			if ($IsWindows == true) {$logFile =~ s/\//\\/g;}
			$msg = sprintf(OpsB::Common::MSG_LogLocation, $logFile);
			WO($msg, M_INFO);
		}
		
	}
	
	WO("Main: End", M_DEBUG);
} # Main

#
# Continue with the script specific code
#

sub ContinueScript() {
	WO("ContinueScript: Start", M_DEBUG);
	
	#
	# If we are using trusted connection then display "Windows Auth"
	#

	my $displayUser = $ARG_User;
	if ($ARG_Trusted == true) {$displayUser = $MSG_TrustedUser;}
	
	WO(sprintf($MSG_CheckingServer, $ARG_DBType, $ARG_Server, $ARG_Port, $displayUser), M_INFO);
	
	#
	# Start by checking the server version
	#
	
	my $versionData = OpsB::Database::GetServerVersion($ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $ARG_DBType, $ARG_SID);

	if (length($versionData) == 0) {
		WO(sprintf($MSG_ServerFail, $ARG_DBType), M_FATAL);
		return;
	}
	
	#
	# Figure out the "Friendly" version - ie SQL V9 is 2005
	#

	my $installedFriendly = OpsB::Database::GetServerFriendlyName($settingsData, $ARG_DBType, $versionData);

	#
	# Read supported version information
	#
	
	my $key = sprintf("<VersionInfo %s", $ARG_DBType);
	my $requiredVersion = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $key)), "Version");
	my $friendlyName = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $key)), "VersionName");
	
	#
	# Initial message using "friendly" if available
	#
	
	my ($msg, $sev) = (sprintf($MSG_ServerVersion, $versionData), M_OK);
	if (length($installedFriendly) > 0) {$msg = sprintf($MSG_ServerVersionFriendly, $installedFriendly, $versionData);}
	
	#
	# Now check this is OK
	#
	
	if (OpsB::Common::MyCompare($versionData, $requiredVersion) == -1) {
		#
		# Needs to be updated
		#
		
		$msg .= sprintf($MSG_ServerNeedsUpdating, $OBMVersion, $ARG_DBType, $requiredVersion, $friendlyName);
		$sev = M_WARN;
	}
	else {
		#
		# Is OK
		#
		
		$msg .= sprintf($MSG_ServerSupported, $OBMVersion);
	}
	
	WO($msg, $sev);
	
	ProcessServerSettings();
	ProcessAdditionalSettings();
	
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Additional Server settings to process
#

sub ProcessAdditionalSettings() {
	WO("ProcessAdditionalSettings: Start", M_DEBUG);
	
	#
	# CPu/TempDB/Index/DataFile queries
	#
	
	my $cpuSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s CPUQuery", $ARG_DBType))), "QueryString"));
	my $cpuName = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s CPUQuery", $ARG_DBType))), "Name"));
	my $cpuQuery = GetQueryFromTag($cpuSettings);

	my $tempdbSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s TempDBQuery", $ARG_DBType))), "QueryString"));
	my $tempdbName = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s TempDBQuery", $ARG_DBType))), "Name"));
	my $tempdbQuery = GetQueryFromTag($tempdbSettings);

	my $indexSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s IndexQuery", $ARG_DBType))), "QueryString"));
	my $indexName = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s IndexQuery", $ARG_DBType))), "Name"));
	my $indexQuery = GetQueryFromTag($indexSettings);

	my $dataFilesSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s DataFilesQuery", $ARG_DBType))), "QueryString"));
	my $dataFilesName = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s DataFilesQuery", $ARG_DBType))), "Name"));
	my $dataFilesQuery = GetQueryFromTag($dataFilesSettings);

	#
	# Initially this is only for SQL but we may expand. See what values we got here
	#

	our $MSG_CheckItem = "Checking %s ...";
	
	if ((length($cpuQuery) > 0) && (length($tempdbQuery) > 0)) {
		WO(sprintf($MSG_CheckItem, $tempdbName), M_INFO);
		DoTempDB($cpuQuery, $tempdbQuery);
	}
	
	if ((length($ARG_DB) > 0) && (length($indexQuery) > 0)) {
		#
		# Only do indexing checks if the database was specified
		#
		
		WO(sprintf($MSG_CheckItem, (sprintf($indexName, $ARG_Frag))), M_INFO);
		DoTableIndexes((sprintf($indexQuery, $ARG_DB, $ARG_Frag)));
	}
	
	if ((length($ARG_DB) > 0) && (length($dataFilesQuery) > 0)) {
		#
		# Defrag checks only done on windows, but we can get the file information on both platforms
		#
		
		WO(sprintf($MSG_CheckItem, $dataFilesName), M_INFO);
		DoDataFiles(sprintf($dataFilesQuery, $ARG_DB));
	}
	
	WO("ProcessAdditionalSettings: End", M_DEBUG);
} #ProcessAdditionalSettings

#
# Check file fragmentation
#

sub DoDataFiles() {
	my $query = shift;
	WO("DoDataFiles: End", M_DEBUG);

	my $dfData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $ARG_DBType, $ARG_SID);
	
	if (length($dfData) == 0) {
		WO("");
		return; # Any error already reported, but might have no "bad" indexes
	}

	my $systemDisk = OpsB::Common::ExpandEnv("%SystemDrive%"); # Checking for data files on this drive
	
	#
	# Loop through the files now and pick up the fragmentation if we can. Also check to see whether or not files are on the system disk
	#
	
	my $csvData = "File (database $ARG_DB),Size,Fragments,Information,Sev";
	
	foreach my $line((split(chr(10), $dfData))) {
		my @lineData = split(/,/, $line);
		my ($devHost, $devFile, $devSize) = ($lineData[0], $lineData[1], $lineData[2]);
		my ($fileSize, $fileFragments, $information, $sev) = ("N/A", "N/A", "", M_NONE);
		
		if (lc $devHost eq lc $My_Name) {
			#
			# We can check the fragmentation of a local file, plus check it is on the system disk. Otherwise we just show it
			#
			
			if (-e $devFile) {
				my $cmd = sprintf("\"%s\" -action frag -input \"%s\" -rawdata", $MF_UTIL, $devFile);
				my ($ok, $rc, $stdout, $stderr) = OpsB::Common::RunCommand($cmd);
				
				if ($ok) {
					#
					# Information should be size, fragments
					#
					
					my @fileDetail = split(/,/, $stdout);
					($fileSize, $fileFragments) = ($fileDetail[0], $fileDetail[1]);
					chomp $fileFragments;
					
					if ($fileFragments > $FRAG_Warn) {
						$sev = M_WARN;
						$information = $MSG_DBFileGettingFragmented;
					}
					
					if ($fileFragments > $FRAG_Error) {
						$sev = M_ERROR;
						$information = $MSG_DBFileDeFrag;
					}
					
					#
					# Check about the file being on the system disk
					#
					
					my ($onSys, $driveInfo) = (false, substr($devFile, 0, length($systemDisk)));
					if (lc $driveInfo eq lc $systemDisk) {$onSys = true;}
					
					if ($onSys) {
						
						if (length($information) == 0) {
							$information = $MSG_DBFileOnSys;
						}
						else {
							$information .= $MSG_DBFileAlsoOnSys
						}
						
						if ($sev < M_WARN) {$sev = M_WARN;}
					}
					
				}
				else {
					$information = sprintf($MSG_DBFileError, $rc);
					$sev = M_WARN;
				}
				
			} # found file
			else {
				$information = $MSG_DBFileMissing;
				$sev = M_WARN;
			}
			
		} # File on this host
		else {
			$information = sprintf($MSG_DBFileRemote, $devHost);
		}
		
		#my $newLine = sprintf("\n%s,%s,%s,%s,%s", $devFile, $fileSize, $fileFragments, $information, $sev);
		#WO($newLine);
		$devFile =~ s/\\/\//g;
		$csvData .= sprintf("\n%s,%s,%s,%s,%s", $devFile, OpsB::Common::ConvertToMBorGB($devSize), $fileFragments, $information, $sev);
	} # loop
	
	WO("");
	OpsB::Common::CSVToTable($csvData, ",", false, true);
	WO("");
	WO("DoDataFiles: End", M_DEBUG);
} # DoDataFiles
#
# Get Table indexes
#

sub DoTableIndexes() {
	my $query = shift;
	WO("DoTableIndexes: Start", M_DEBUG);
	
	my $indexData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $ARG_DBType, $ARG_SID);
	
	if (length($indexData) == 0) {
		WO("");
		return; # Any error already reported, but might have no "bad" indexes
	}

	#
	# Add a header
	#
	
	$indexData = sprintf("Table Name,Index Name,Fragmentation Percent,Action to Take\n%s", $indexData);
	
	WO("");
	OpsB::Common::CSVToTable($indexData, ",", false, false);
	WO("");
	
	WO("DoTableIndexes: Start", M_DEBUG);
} # DoTableIndexes
#
# Get the TempDB information
#

sub DoTempDB() {
	my ($cpuQuery, $tempdbQuery) = @_;
	WO("DoTempDB: Start", M_DEBUG);
	
	#
	# Get the CPU count first as the number of files is dependent on the CPU count
	#
	
	my $cpuData = OpsB::Database::SimpleQuery($cpuQuery, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $ARG_DBType, $ARG_SID);
	
	my $logicalCPUCount = 0;
	
	if (length($cpuData) == 0) {
		our $MSG_CPUCountFailed = "Unable to obtain CPU count, resulting data will be informational only";
		WO($MSG_CPUCountFailed, M_WARN);
	}
	else {
		#
		# Logical CPU count should be the first item
		#
		
		$logicalCPUCount = (split(/,/, $cpuData))[0];
	}
	
	#
	# Now the tempdb files information
	#
	
	my $tempData = OpsB::Database::SimpleQuery($tempdbQuery, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $ARG_DBType, $ARG_SID);
	
	if (length($tempData) == 0) {
		our $MSG_TempDBFailed = "Unable to determine configuration of tempdb";
		WO($MSG_TempDBFailed, M_ERROR);
		return;
	}
	
	#
	# First, find out how many files for Data - split and filter to get the count
	#
	

	my $numData = scalar (grep(/\,Data/, (split(chr(10), $tempData))));

	#
	# The output is in csv so add headers for display
	#
	
	$tempData = sprintf("Device Name,Size,Auto Growth,Size,Type\n%s", $tempData);
	WO("");
	OpsB::Common::CSVToTable($tempData, ",", false, false);
	WO("");
	
	#
	# Figure out if we meet the guidelines
	#
	
	my $numFiles = 8;
	if ($logicalCPUCount < $numFiles) {$numFiles = $logicalCPUCount;}
	
	our $MSG_TempdDBFiles = "The server has %s logical CPUs and %s tempdb data files. ";
	my ($msg, $sev) = (sprintf($MSG_TempdDBFiles, $logicalCPUCount, $numData), M_OK);
	
	if ($numData < $numFiles) {
		$sev = M_WARN;
		my $newRequired = $numFiles - $numData;
		our $MSG_RequiredTempdB = "Another %s data files should be added for optimal performance";
		$msg .= sprintf($MSG_RequiredTempdB, $newRequired);
	}
	else {
		our $MSG_TempdDBFilesOK = "The tempdb has been optimised for the number of CPUs";
		$msg .= $MSG_TempdDBFilesOK;
	}
	
	WO($msg, $sev);
	WO("");
	WO("DoTempDB: End", M_DEBUG);
} #DoTempDB
#
# Read the settings file for the query in the tag
#

sub GetQueryFromTag() {
	my $tag = shift;
	WO("GetQueryFromTag: Start", M_DEBUG);

	my $return = "";
	
	my ($keyStart, $keyEnd) = (sprintf("<%s>", $tag), sprintf("</%s>", $tag));
	my $query = OpsB::Common::FindLineWithKey($settingsData, $keyStart, $keyEnd);

	if (length($query) > 0) {
		#
		# Remove the tag
		#
		
		$query = substr($query, length($keyStart));
		$query = OpsB::Database::CleanQueryString($query);
		$return = $query;
	}
	
	WO("GetQueryFromTag: End", M_DEBUG);
	return $return;
} #GetQueryFromTag
#
# After successfully getting the version information, now get the settings information
#

sub ProcessServerSettings() {
	WO("ProcessServerSettings: Start", M_DEBUG);
	
	#
	# Start by checking to see if there are any settings to process for this server type
	#
	
	my $readSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s Settings", $ARG_DBType))), "QueryString"));
	my $updateSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s UpdateSettings", $ARG_DBType))), "QueryString"));
	my $reloadSettings = OpsB::Common::GetAttributeFromData(((OpsB::Common::FindLineWithKey($settingsData, sprintf("<%s ReloadSettings", $ARG_DBType))), "QueryString"));
	
	#
	# If there are no settings definitions then stop here
	#
	
	if (length($readSettings) == 0) {
		WO("No defined settings queries for database type $ARG_DBType", M_DEBUG);
		return;
	}
	
	our $MSG_ServerSettings = "Checking server settings...";
	WO($MSG_ServerSettings, M_INFO);
	WO("");

	#
	# Fetch the query that we will use for listing the settings
	#
	
	my ($keyStart, $keyEnd) = (sprintf("<%s>", $readSettings), sprintf("</%s>", $readSettings));
	my $query = OpsB::Common::FindLineWithKey($settingsData, $keyStart, $keyEnd);

	if (length($query) == 0) {
		our $MSG_SettingsQueryNotFound = "The query to retrieve settings data is missing - it was expected at tag: %s";
		WO(sprintf($MSG_SettingsQueryNotFound, $readSettings), M_ERROR);
		return;
	}
	
	#
	# Remove the tag
	#
	
	$query = substr($query, length($keyStart));
	$query = OpsB::Database::CleanQueryString($query);
	
	#
	# Get the queries for update and reload
	#
	
	($keyStart, $keyEnd) = (sprintf("<%s>", $updateSettings), sprintf("</%s>", $updateSettings));
	my $queryUpdate = OpsB::Common::FindLineWithKey($settingsData, $keyStart, $keyEnd);
	
	#
	# Remove the tag
	#

	if (length($queryUpdate) > 0) {
		$queryUpdate = substr($queryUpdate, length($keyStart));
		$queryUpdate = OpsB::Database::CleanQueryString($queryUpdate);
	}
	
	($keyStart, $keyEnd) = (sprintf("<%s>", $reloadSettings), sprintf("</%s>", $reloadSettings));
	my $queryReload = OpsB::Common::FindLineWithKey($settingsData, $keyStart, $keyEnd);
	
	#
	# Remove the tag
	#
	
	if (length($queryReload) > 0) {
		$queryReload = substr($queryReload, length($keyStart));
		$queryReload = OpsB::Database::CleanQueryString($queryReload);
	}

	#
	# Now get all of the parameters that we need to process
	#
	
	my $filter = sprintf("<%s ParamName=", $ARG_DBType);
	my @params = grep(/$filter/, (split(chr(10), $settingsData)));
	
	#
	# Loop through the parameters that we read from the configuration file
	#
	
	for my $setting(@params) {
		my $paramName = OpsB::Common::GetAttributeFromData($setting, "ParamName");
		my $paramSmall = OpsB::Common::GetAttributeFromData($setting, "Small");
		my $paramMedium = OpsB::Common::GetAttributeFromData($setting, "Medium");
		my $paramLarge = OpsB::Common::GetAttributeFromData($setting, "Large");
		my $paramShowOnly = OpsB::Common::GetAttributeFromData($setting, "ShowOnly");
	
		#
		# Decided which setting that we have read is the one to use in the check
		#
		
		my $checkSetting = $paramSmall;
		if ($ARG_Size eq $Size_Medium) {$checkSetting = $paramMedium;}
		if ($ARG_Size eq $Size_Large) {$checkSetting = $paramLarge;}
		
		#
		# We allow the Xml to specify another setting... ie "Large" might say "Small" instead of a value
		#
		
		if (lc $checkSetting eq "*small*") {$checkSetting = $paramSmall;}
		if (lc $checkSetting eq "*medium*") {$checkSetting = $paramMedium;}
		if (lc $checkSetting eq "*large*") {$checkSetting = $paramLarge;}
		
		#
		# For Show only, set the parameter to <Information only>
		#
		
		if ($paramShowOnly eq "1") {
			$paramSetting{$paramName} = $INFO_Only;
		}
		else {
			$paramSetting{$paramName} = $checkSetting;
		}
		
	}
	
	#
	# Now call the routine to show this information. Add the query and the "shoAll setting
	#
	
	$paramSetting{$TAG_Query} = $query;
	$paramSetting{$TAG_ShowAll} = false;
	
	my ($ok, $found) = GetSettingsFromHash(%paramSetting);
	
	#
	# If all good, see if we have anything to process
	#
	
	if (($ok == true) && ($found > 0)) {
		WO("");
		
		if ($ARG_DBType ne OpsB::Database::DBTYPE_Oracle_String) {
			#
			# Do not currently update Oracle - leave that to the dba
			#
			
			if ($ARG_Set == false) {
				WO($MSG_HowToSet, M_INFO);
			}
			else {
				#
				# Make sure that we are OK to go ahead and make changes
				#
				
				our $MSG_Question_Continue = "Are you sure that you wish to make the above changes";
				my $continue = false;
				
				if ($ARG_Force == true) {
					$continue = true;
				}
				else {
					$continue = OpsB::Common::IsYes($MSG_Question_Continue);
				}
				
				if ($continue == true) {
					MakeConfigurationChanges($ARG_DBType, $query, $queryUpdate, $queryReload);
				}
				else {
					WO($MSG_NoChanges, M_INFO);
				}
			}
			
		}
		else {
			WO(sprintf($MSG_WorkWithDBA, OpsB::Database::DBTYPE_Oracle_String), M_INFO);
		}	
	
	}
	else {
		
		if ($found == 0) {
			WO (sprintf($MSG_SettingsOK, $ARG_Size), M_OK);
		}
	}
	WO("ProcessServerSettings: End", M_DEBUG);
} #ProcessServerSettings

#
# Make changes to the chosen sever type
#

sub MakeConfigurationChanges() {
	my ($dbType, $query, $queryUpdate, $queryReload) = @_;
	WO("MakeConfigurationChanges: Start", M_DEBUG);

	WO("");
	WO(sprintf($MSG_MakingChanges, $dbType), M_INFO);
		
	#
	# Loop through the hash table that we previously set up as it has the parameter names and values
	#
	
	my $ok = true;
	
	foreach my $key (sort keys %updateParams) {
		my $value = $updateParams{$key};
		#WO("Set: $key to value $value");
		
		#
		# Insert information to query
		#
		
		my $cmdToRun = sprintf($queryUpdate, $key, $value);
		#WO($cmdToRun);
		$ok = OpsB::Database::SimpleCommand($cmdToRun, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $dbType, $ARG_SID);
		
		if ($ok == false) {
			my $displayUser = $ARG_User;
			if ($ARG_Trusted == true) {$displayUser = $MSG_TrustedUser;}
			WO(sprintf($MSG_Set_Error, $displayUser), M_ERROR);
			last;
		}
	}
	
	if ($ok == false) {
		return;
	}
	
	if (length($queryReload) > 0) {
		WO($MSG_Reload, M_INFO);
		my $returnData = OpsB::Database::SimpleQuery($queryReload, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $dbType, $ARG_SID);
		
		if ((length($returnData) == 0) || ($returnData =~ /false/i)) {
			WO($MSG_ReloadFailed, M_WARN);
		}
		else {
			our $MSG_ReloadOK = "Configuration reloaded";
			WO($MSG_ReloadOK, M_INFO);
		}
		
	}
	
	#
	# Now display updates
	#
	
	$updateParams{$TAG_Query} = $query;
	$updateParams{$TAG_ShowAll} = true;
	
	WO("");
	WO($MSG_ShowAfterUpdate);
	WO("");
	
	my ($newOK, $found) = GetSettingsFromHash(%updateParams);
	
	WO("");
	WO(sprintf($MSG_PossibleRestart, $dbType), M_INFO);
	WO ("");
	
	WO("MakeConfigurationChanges: End", M_DEBUG);
} # MakeConfigurationChanges
#
# Core code to display settings - input is the hash table to use
#

sub GetSettingsFromHash() {
	my %hash = @_;
	WO("GetSettingsFromHash: Start", M_DEBUG);

	my %outputHash = ();
	my %useHash = ();
	
	my ($baseQuery, $showAll, $dbType, $ok, $rowsFound) = ("", false, $ARG_DBType, false, 0);
		
	#
	# Build the hash to use here based on the input, and that will include the query to use taht was retrieved in the calling routines
	#
	
	foreach my $key(keys %hash) {
		my $value = $hash{$key};
		
		if (($key eq $TAG_Query) || ($key eq $TAG_ShowAll)) {
			#
			# Set up the query to use and whether or not we will check the values, or simply show everything in the hash
			#
			
			if ($key eq $TAG_Query) {
				$baseQuery = $value;
			}
			else {
				$showAll = $value;
			}
			
		}
		else {
			#
			# Build the new hash
			#
			
			$useHash{$key} = $value;
		}
		
	}

	#
	# We have a new hash table that has only the values to query for, the baseQuery is "select <stuff> from <table> where name in (%s) - so
	# we need to fill in the names from the new hash
	#
	
	my $clause = "";
	
	foreach my $key (keys %useHash) {
		my $value = sprintf("'%s'", $key);
		if (length($clause) == 0) {$clause = $value;} else {$clause .= sprintf(", %s", $value);}
	}
	
	my $query = sprintf($baseQuery, $clause);
	
	#
	# Run the Query
	#
	
	my $resultsData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DB, $dbType, $ARG_SID);

	if (length($resultsData) > 0) {
		#
		# Data came back - so process it#
		#
		
		$ok = true;
		
		for my $paramRow((split(chr(10), $resultsData))) {
			#
			# The row should be name,value,displayvalue,type,desc
			#
			# But the description might have commas - so we need to check for that and "stich" the data back together. If the desc has
			# commas then it is encapsulated in quotes
			#
			
			my @rowData = split(/,/, $paramRow);
			my ($desc, $cValueAdjusted) = ("", "");
			
			if (scalar @rowData > 5) {
				#
				# Presumably has commas - so loop through all elements > 4 and stich them together. Without the quotes
				#
				
				for (my $i=5;$i <scalar @rowData;$i ++) {
					my $item = $rowData[$i];
					if (substr($item, 0, 1) eq "\"") {$item = substr($item, 1);}
					if (substr($item, length($item) -1, 1) eq "\"") {$item = substr($item, 0, length($item) -1);}
					if (length($desc) == 0) {$desc = $item;} else {$desc .= sprintf(",%s", $item);}
				}
			}
			else {
				$desc = $rowData[4]
			}
			
			#
			# Now get all the information for this row
			#
			
			my($pName, $pRaw, $pDisplay, $pType, $pRestart) = ($rowData[0], $rowData[1], $rowData[2], $rowData[3], $rowData[4]);
			
			if (lc substr($pRestart, 0, 1) eq "t") {
				$pRestart = "Yes";
			}
			else {
				$pRestart = "No";
			}
			
			my $cValue = $paramSetting{$pName}; # Always use the main hash as the update one may have been adjusted!
			
			#
			# In some cases - namely numeric - the display value takes 1024 and shows 1GB, so we need to look 
			# at this as we will need to know the exact value to set (and display)
			#
			
			my ($currentDisplay, $newDisplay, $mismatch) = ($pRaw, $cValue, false);
			
			if ($cValue eq $INFO_Only) {
				$mismatch = true;
			}
			else {
				
				if (($pType == 3) || ($pType == 6)) {
					#
					# Numeric Value -  https://docs.oracle.com/cd/B28359_01/server.111/b28320/dynviews_2085.htm#REFRN30176
					#
					
					my ($pDisplayNumeric, $removed) = OpsB::Common::MakeStringNumeric($pDisplay, true);
					
					#
					# Figure out if the actual value is different from the display value - if so then work out the scale factor.
					#
					
					my ($factor, $divideBy) = (1, false);
					my $equivalence = OpsB::Common::MyCompare($pRaw, $pDisplayNumeric);	# 0 means the same, -1 means left smaller than right, 1 means left larger than right
					
					if ($equivalence !=0) {
						$factor = $pDisplayNumeric / $pRaw;
						
						if ($equivalence == 1) {
							$factor = $pRaw / $pDisplayNumeric;
							$divideBy = true;
						}
						
					}
					
					#
					# Now apply the factor to the value we are checking, for display purposes
					#
					
					$cValueAdjusted = $cValue * $factor;
					if ($divideBy == true) {$cValueAdjusted = $cValue / $factor;}
					
					#
					# Now see if things are different
					#
					
					if ($pRaw < $cValue) { # Only if current is smaller that recommended....
						$mismatch = true;
					}
					
					#
					# For Display
					#
					
					if ($pRaw ne $pDisplay) {
						$currentDisplay = sprintf("%s (%s)", $pRaw, $pDisplay);
					}
					
					if ($cValue ne $cValueAdjusted) {
						$newDisplay = sprintf("%s (%s %s)", $cValue, $cValueAdjusted, $removed);
					}
					
				} # Numeric check
				
				if ($pType == 1) {
					my ($pVal, $cVal) = ("TRUE", "TRUE");
					if ($pRaw =~ /false/i) {$pVal = "FALSE";}
					if ($cValue =~ /false/i) {$cVal = "FALSE";}
					
					if ($pVal ne $cVal) { $mismatch = true;}
					
					#
					# For display
					#
					
					($newDisplay, $currentDisplay, $cValueAdjusted) = ($cValue, $pRaw, $cValue);
				} # Boolean check
				
				if ($pType == 2) {
					if (lc $pRaw ne lc $cValue) {$mismatch = true;}
					
					#
					# For Display
					#
					
					($newDisplay, $currentDisplay, $cValueAdjusted) = ($cValue, $pRaw, $cValue);				
				} # String check

			}
					
			#
			# Build the information to add to hash table - do this because we can sort the has table
			#
			
			if ($showAll == true) {
				#
				# Swap description for "is a restarted required"
				#
				
				$desc = $pRestart
			}
			
			my $sev = M_OK;
			if ($mismatch == true) {
				$sev = M_WARN;
				$rowsFound +=1;
			}
			
			my $hashValue = sprintf("%s~%s~%s~%s", $currentDisplay, $newDisplay, $desc, $sev);
			
			if (($mismatch == true) || ($showAll == true) ||($ARG_ShowOK == true)) {
				$outputHash{$pName} = $hashValue;
				
				if (($mismatch == true) && ($cValue ne "<Information Only>") && ($showAll == false)) {
					#
					# Add to the hash for settings that we change
					#
					
					$updateParams{$pName} = $cValue;
				}
			}
		}
		
		#
		# If there is anyting to show then show it... convert the hash to a csv string 
		#
		
		if (scalar keys %outputHash > 0) {
			#
			# Something to display
			#
			
			my $csvString = "Parameter~Current Setting~Recommended ($ARG_Size Depl.)~Description~Sev";
			
			if ($showAll == true) {
				$csvString = "Parameter~Current Setting~Recommended ($ARG_Size Depl.)~Restart Required~Sev";
			}
			
			for my $key(sort keys %outputHash) {
				my $new = sprintf("%s~%s", $key, $outputHash{$key});
				$csvString .= sprintf("\n%s", $new);				
			}
			
			OpsB::Common::CSVToTable($csvString, "~", false, true);
		}
		
	} # Got query results
	
	
	WO("GetSettingsFromHash: End", M_DEBUG);
	return $ok, $rowsFound;
} # GetSettingsFromHash
#
# Get the inputs for this script_name
#

sub GetInputs() {
	#
	# Get the standard inputs
	#
	
	$ARG_Debug = OpsB::Common::FindSwitch("debug");
	$ARG_Color = OpsB::Common::FindSwitch("nocolor");
	$ARG_Log = OpsB::Common::FindSwitch("log");
	$ARG_Quiet = OpsB::Common::FindSwitch("quiet");
	$ARG_NoWelcome = OpsB::Common::FindSwitch("nowelcome");
	$ARG_Quiet = OpsB::Common::FindSwitch("quiet");
	$ARG_Help = OpsB::Common::FindSwitch("help") || OpsB::Common::FindSwitch("h") || OpsB::Common::FindSwitch("\?");
	
	#
	# Switch around the color settings - found value for "nocolor" so if that is true, set "ARG_Color" to false;
	#
	
	if ($ARG_Color == true) {$ARG_Color = false;} else {$ARG_Color = true;}
	
	#
	# Script specific args and switches to be handled below
	#

	$ARG_Set = OpsB::Common::FindSwitch("set");
	$ARG_Server = OpsB::Common::FindArg("server");
	$ARG_Port = OpsB::Common::FindArg("port");
	$ARG_DB = OpsB::Common::FindArg("db");
	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_PWD = OpsB::Common::FindArg("pwd");
	$ARG_Trusted = OpsB::Common::FindSwitch("trusted");
	$ARG_SID = OpsB::Common::FindArg("sid");
	$ARG_DBType = OpsB::Common::FindArg("dbtype");
	$ARG_Set = OpsB::Common::FindSwitch("set");
	$ARG_Force = OpsB::Common::FindSwitch("force");
	$ARG_Size = OpsB::Common::FindArg("size");
	$ARG_ShowOK = OpsB::Common::FindSwitch("showok");
	$ARG_Frag = OpsB::Common::FindArg("frag");
	
} # GetInputs

#
# Make sure the inputs are ok and change adjust as needed
#

sub CheckInputs() {
	WO("CheckInputs: Start", M_DEBUG);
	
	#
	# Change value to fals if any information is bad. Se the Error string to hold all error messages so they can be displayed later
	#
	
	my ($ok, $error) = (true, "");
	
	if (length($ARG_Server) == 0) {
		$ARG_Server = $My_Name;
	}
	
	if (length($ARG_DBType) == 0) {
		#
		# Must have this so prompt for it
		#
		
		my $answer = OpsB::Common::GetAnswer(sprintf($MSG_DBType_Prompt, $DBTYPE_MSSQL, OpsB::Database::DBTYPE_MSSQL_String, $DBTYPE_Oracle, OpsB::Database::DBTYPE_Oracle_String, $DBTYPE_PG, OpsB::Database::DBTYPE_PG_String));
		my ($numeric, $dummy) = OpsB::Common::MakeStringNumeric($answer);
		WO("");
		
		my $found = false;
		
		if (length($numeric) > 0) {
			
			if ($numeric < 1 || $numeric > 3) {
				$error = OpsB::Common::AddString($error, sprintf($MSG_DBType_Invalid, $numeric), "\n");
				$ok = false;
			}			
			else {
				$ARG_DBType = OpsB::Database::DBTYPE_MSSQL_String;
				if ($numeric == $DBTYPE_Oracle) {$ARG_DBType = OpsB::Database::DBTYPE_Oracle_String;}
				if ($numeric == $DBTYPE_PG) {$ARG_DBType = OpsB::Database::DBTYPE_PG_String;}
			}
			
		}
		else {
			#
			# Allow the answer to have been Oracle/MSSQL/Postgres
			#
			
			if (lc $answer eq substr(lc $DBType_MSSQL_Input, 0, length($answer))) {$ARG_DBType = OpsB::Database::DBTYPE_MSSQL_String;}
			if (lc $answer eq substr(lc OpsB::Database::DBTYPE_Oracle_String, 0, length($answer))) {$ARG_DBType = OpsB::Database::DBTYPE_Oracle_String;}
			if (lc $answer eq substr(lc OpsB::Database::DBTYPE_PG_String, 0, length($answer))) {$ARG_DBType = OpsB::Database::DBTYPE_PG_String;}
			
			if (length($ARG_DBType) == 0) {
				$error = OpsB::Common::AddString($error, sprintf($MSG_DBType_Invalid, $answer), "\n");
				$ok = false;
			}
			
		}		
		
	}
	else {
		#
		# Verify that the input was valid
		#
		
		my $answer = $ARG_DBType;
		$ARG_DBType = ""; # For later checkInputs
		
		my ($numeric, $dummy) = OpsB::Common::MakeStringNumeric($answer);		
		my $found = false;
		
		if (length($numeric) > 0) {
			
			if ($numeric < 1 || $numeric > 3) {
				$error = OpsB::Common::AddString($error, sprintf($MSG_DBType_Invalid, $numeric), "\n");
				$ok = false;
			}			
			else {
				$ARG_DBType = OpsB::Database::DBTYPE_MSSQL_String;
				if ($numeric == $DBTYPE_Oracle) {$ARG_DBType = OpsB::Database::DBTYPE_Oracle_String;}
				if ($numeric == $DBTYPE_PG) {$ARG_DBType = OpsB::Database::DBTYPE_PG_String;}
			}
			
		}
		else {
			#
			# Allow the answer to have been Oracle/MSSQL/Postgres
			#
			
			if (lc $answer eq substr(lc $DBType_MSSQL_Input, 0, length($answer))) {$ARG_DBType = OpsB::Database::DBTYPE_MSSQL_String;}
			if (lc $answer eq substr(lc OpsB::Database::DBTYPE_Oracle_String, 0, length($answer))) {$ARG_DBType = OpsB::Database::DBTYPE_Oracle_String;}
			if (lc $answer eq substr(lc OpsB::Database::DBTYPE_PG_String, 0, length($answer))) {$ARG_DBType = OpsB::Database::DBTYPE_PG_String;}
			
			if (length($ARG_DBType) == 0) {
				$error = OpsB::Common::AddString($error, sprintf($MSG_DBType_Invalid, $answer), "\n");
				$ok = false;
			}
			
		}		
	} # DBType
	
	#
	# On Windows, SQL can use Trusted connection so set the user/password to blank
	#
	
	if ($ARG_Trusted == true) {
		
		if (lc $ARG_DBType ne lc OpsB::Database::DBTYPE_MSSQL_String) {
			#
			# Not allowed if not SQL
			#
			
			$error = OpsB::Common::AddString($error, $MSG_TrustedOnlyWithSQL, "\n");
			$ok = false;
		}
		else {
			
			if ($IsWindows == false) {
				#
				# Only on Windows
				#
				
				$error = OpsB::Common::AddString($error, $MSG_TrustedOnlyOnWindows, "\n");
				$ok = false;
			}
			else {
				$ARG_User = "";
				$ARG_PWD = "";
			}
			
		}
	}
	
	#
	# Verify the port is OK, set to defaults if not
	#
	
	my $defaultPort = OpsB::Database::PORT_SQL_Default;
	
	if ($ARG_DBType eq OpsB::Database::DBTYPE_Oracle_String) {
		$defaultPort = OpsB::Database::PORT_Oracle_Default;
	
		if (length($ARG_SID) == 0) {
			$error = OpsB::Common::AddString($error, $MSG_NoSID, "\n");
			$ok = false;
		}
		
	}
	
	if ($ARG_DBType eq OpsB::Database::DBTYPE_PG_String) {$defaultPort = OpsB::Database::PORT_PG_Default;}
	
	$ARG_Port = OpsB::Common::GetNumericFromString($ARG_Port, 0, 32767, $defaultPort);
	
	if ($ARG_Trusted == false) {
	
		if (length($ARG_User) == 0) {
			$error = OpsB::Common::AddString($error, $MSG_NoUser, "\n");
			$ok = false;
		}
		
		if (length($ARG_PWD) == 0) {
			$error = OpsB::Common::AddString($error, $MSG_NoPWD, "\n");
			$ok = false;
		}

	}
		
	if ($useSettings == false) {
		#
		# No point going on!
		#
		
		$error = OpsB::Common::AddString($error, $MSG_NoSettings, "\n");
		$ok = false;
	}
	
	#
	# Make size "small" if undefined or "wrong"
	#
	
	if (length($ARG_Size) == 0) {
		$ARG_Size = $Size_Small;
	}
	
	if (lc $ARG_Size eq lc substr($Size_Small, 0, length($ARG_Size))) {$ARG_Size = $Size_Small;}
	if (lc $ARG_Size eq lc substr($Size_Medium, 0, length($ARG_Size))) {$ARG_Size = $Size_Medium;}
	if (lc $ARG_Size eq lc substr($Size_Large, 0, length($ARG_Size))) {$ARG_Size = $Size_Large;}

	if (($ARG_Size ne $Size_Small) && ($ARG_Size ne $Size_Medium) && ($ARG_Size ne $Size_Large)) {
		$error = OpsB::Common::AddString($error, (sprintf($MSG_InvalidSize, $ARG_Size)), "\n");
		$ok = false;
	}
	
	$ARG_Frag = OpsB::Common::GetNumericFromString($ARG_Frag, 0, 100, 30);
	
	return $ok, $error;
	
	WO("CheckInputs: End", M_DEBUG);
} # CheckInputs

#
# Show our help
#

sub ShowHelp() {
	
	WO("");
	WO(OpsB::Common::MSG_Help_Start);
	WO("");
		
	#
	# Add Script Specific help
	#
	
	WO("  -server <server>\tHost name (or Host and instance) of the database server. Localhost will be used if this is not supplied");
	WO("  -port <port>\t\tTCPIP port for server connection (optional)");
	WO("  -user <user>\t\tDatabase server login");
	WO("  -pwd <password>\tPassword for database user");
	WO("  -sid <SID>\t\tRequired for Oracle connection");
	WO("  -trusted\t\tFor SQL Server when the script runs on Windows - use Windows authentication");
	WO(sprintf("  -dbtype <type>\tThe database type (must be \"%s\", \"%s\" or \"%s\")", OpsB::Database::DBTYPE_Oracle_String, OpsB::Database::DBTYPE_PG_String, $DBType_MSSQL_Input));
	WO("  -set\t\t\tUse this switch to commit changes if necessary");
	WO("  -force\t\tUse this switch to disable prompts if changes are necessary");
	WO(sprintf("  -size <size>\t\tUse this argument to specify the configuration size for checks (must be one of \"%s\", \"%s\" or \"%s\")", $Size_Small, $Size_Medium, $Size_Large));
	WO("  -frag <percent>\tFragmentation percent threshold for checking database indexes. Default is 30");

	OpsB::Common::CommonHelp();
	

	
}

#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();