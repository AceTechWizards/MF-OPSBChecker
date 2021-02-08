#!/usr/bin/perl

# ++
# File:     
# Created:  
# Reason:   
# --
# Abstract: 
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
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
use OpsB::Common qw(WO true false $IsWindows M_NONE M_INFO M_OK M_WARN M_ERROR M_FATAL M_DEBUG $ARG_Debug $ARG_Log $ARG_Color $ARG_Quiet $ARG_Timeout $ARG_NoWelcome $ARG_Help M_NOTE); 

use OpsB::HPBSM;
use OpsB::HPBSM qw(TopazDir HP_BSM_MODULE_VERSION $Java);

use OpsB::Database;
use OpsB::Database qw(DATABASE_MODULE_VERSION $DBTYPE_MSSQL $DBTYPE_Oracle $DBTYPE_PG);

#
# required
#

our $scriptVersion = "2020.12";
our $scriptArgs = "user,pwd,server,port,sid,dbevent,dbtype,trusted,dbmgmt,etidetail,dbrtsm";

#
# Messages
#

our $DBType_MSSQL_Input = OpsB::Database::DBTYPE_MSSQL_String;
$DBType_MSSQL_Input =~ s/ //g; # Do this to remove spaces from "MS SQL" to make the input easier - MSSQL

our $MSG_DBType_Prompt = "Specify the Database Server Type (%s=%s, %s=%s, %s=%s)";
our $MSG_DBType_Invalid = sprintf("\tThe -dbtype %s is invalid, it must be a value between 1 and 3 or one of \"%s\", \"%s\" or \"%s\"", "%s", $DBType_MSSQL_Input, OpsB::Database::DBTYPE_Oracle_String, OpsB::Database::DBTYPE_PG_String);
our $MSG_TrustedOnlyWithSQL = sprintf("\tTrusted connection is only allowed with %s database type", OpsB::Database::DBTYPE_MSSQL_String);
our $MSG_TrustedOnlyOnWindows = "\tTrusted commection is only allowed when running the script on Windows";
our $MSG_NoUser = "\tNo user was provided for connecting to the server";
our $MSG_NoPWD = "\tNo password was provided for connecting to the server";
our $MSG_TrustedUser = "<Windows Authentication>";
our $MSG_NoSID = "\tFor the Oracle Database type, the SID must be specified";
our $MSG_ETI_Mapping_Custom_Summary = "There are %s Indicator Mapping Rules that still require Flash for editing. To list these rules, check the documentation";
our $MSG_ETI_Mapping_Custom = "There are some custom Indicator Mapping Rules that still require Flash for editing:%s\n";
our $MSG_ServerInfo_Check = "%s Server: %s, CPU count: %s - RAM %s GB. Minimum recommended: CPUs: %s - RAM: %s GB";
our $MSG_ServerInfo	= "%s Server: %s, CPU count: %s - RAM: GB";
our $MSG_NoSize = "Unable to determine the configuration deployment size";
our $MSG_BadConfig = "Unable to determine requirements from configuration file, no comparison checks will be made";
our $MSG_CheckingSize = "Checking configured servers for \"%s\" sized deployment ...";
our $MSG_IsEmbedded = "Postgres server is embedded";
our $MSG_NotEmbedded = "Postgres server is not embedded";
our $MSG_CheckEmbedded = "Checking to see if Postgres is embedded ...";
our $MSG_CP_Multiple = "%s Content Packs (%s) found in the UCMDB database. Only the most recent Content Pack is required, so grooming will save space in the database";
our $MSG_CPOK = "One Content Pack found (%s) in the UCMDB database";
our $MSG_CPCheck = "Checking Content Packs in the UCMDB database \"%s\" ...";
our $MSG_Mgmt_Checks = "Checking management database \"%s\" ...";
our $MSG_Event_Checks = "Checking event database \"%s\" ...";

#
# Script Specific Arguments
#

our $ARG_Server = "";
our $ARG_User = "";
our $ARG_PWD = "";
our $ARG_Port = 0;
our $ARG_SID = "";
our $ARG_DBEvent = "";
our $ARG_DBMgmt = "";
our $ARG_DBType = "";
our $ARG_Trusted = false;
our $ARG_ETI_Detail = false;
our $ARG_DBRTSM = "";

#
# Additional
#

#
# For version information
#

our ($useVersion, $version_data, $versionError) = (false, "", "");
our $versionsFile = OpsB::Common::GetScriptDir($0) . OpsB::Common::VERSIONS_FILE;
if (-e $versionsFile) {($useVersion, $version_data, $versionError) = OpsB::Common::ReadFileToString($versionsFile);}

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
	
	my $argValues = "";	
	OpsB::Common::ShowInputs($argValues);
	
	#
	# Show banner
	#
	
	my $additionalModules = sprintf("DB Version: %s", DATABASE_MODULE_VERSION);
	my $description = "Database checking script";
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
		WO($inputsError, M_FATAL);
		WO("");
		return;
	}
	
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
	# If the event database is provided then do the event database checks
	#
	
	if (length($ARG_DBMgmt) > 0) {
		DoMgmtChecks();
	}
	
	#
	# If the event database is provided then do the event database checks
	#
	
	if (length($ARG_DBEvent) > 0) {
		DoEventChecks();
	}
	
	if (length($ARG_DBRTSM) > 0){
		#
		# RTSM checks
		#

		DoRTSMChecks();
	}

	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Do the checks on the mgmt database
#

sub DoRTSMChecks() {
	WO("DoRTSMChecks Start", M_DEBUG);
	my $msg = "";

	#
	# First Check for the configuration type
	#

	if ($ARG_NoWelcome == false) {
		WO(sprintf($MSG_CPCheck, $ARG_DBRTSM), M_INFO);
	}

	my $query = "select count(1), sum(datalength(CP_BYTES)) from CONTENT_PACKS"; # SQL Server

	if ($ARG_DBType eq OpsB::Database::DBTYPE_Oracle_String) {
		$query = "select count(1), sum(length(CP_BYTES)) from CONTENT_PACKS";
	}

	if ($ARG_DBType eq OpsB::Database::DBTYPE_PG_String) {
		$query = "select count(1), sum(octet_length(CP_BYTES)) from CONTENT_PACKS";
	}

	my $cpData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DBRTSM, $ARG_DBType, $ARG_SID);

	if (length($cpData) == 0) {
		return;
	}

	my $numCP = (split(/,/, $cpData))[0];
	my $sizeBytes = (split(/,/, $cpData))[1];
	my $sev = M_OK;

	if ($numCP == 1) {
		$msg = sprintf($MSG_CPOK, OpsB::Common::ConvertToMBorGB($sizeBytes));
	}
	else {
		$msg = sprintf($MSG_CP_Multiple, $numCP, $sizeBytes);
		$sev = M_NOTE;
	}

	WO($msg, $sev);

	WO("DoRTSMChecks Start", M_DEBUG);
}# DoRTSMChecks

#
# Do the checks on the mgmt database
#

sub DoMgmtChecks() {
	WO("DoMgmtChecks Start", M_DEBUG);
	my $msg = "";

	#
	# First Check for the configuration type
	#

	if ($ARG_NoWelcome == false) {
		WO(sprintf($MSG_Mgmt_Checks, $ARG_DBMgmt), M_INFO);
	}

	my $query = "select DEP_LEVEL from DEPLOY_CONF where APP_NAME = 'Model' and TYPE = 'CURRENT'";
	my $sizeData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DBMgmt, $ARG_DBType, $ARG_SID);

	if (length($sizeData) == 0) {
		#
		# Something went wrong here as this informationmust be present
		#

		WO($MSG_NoSize, M_ERROR);
		return;
	}

	#
	# Check Embedded Postgres
	#

	if ($ARG_DBType eq OpsB::Database::DBTYPE_PG_String) {
		#
		# Clesrly embedded Postgres is only an option if we know the DB os Postgres
		#

		WO($MSG_CheckEmbedded, M_INFO);

		$query = "select DEP_LEVEL from DEPLOY_CONF where APP_NAME = 'PostgresEmbedded' and TYPE = 'CURRENT'";
		my $embeddedData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DBMgmt, $ARG_DBType, $ARG_SID);

		my $sev = M_OK;
		$msg = $MSG_NotEmbedded;

		if (length($embeddedData) > 0) {
			#
			# Check to see if it is the case
			#

			if ($embeddedData =~ /ON/i) {
				#
				# yes it is
				#

				$sev = M_INFO;	# Only an issue on CDF so leave this as informational
				$msg = $MSG_IsEmbedded;
			}

		}

		WO($msg, $sev);
	}

	WO(sprintf($MSG_CheckingSize, $sizeData), M_INFO);

	#
	# Use the Size to get the information relating to memory and CheckInputs
	#

	my $key = (sprintf("<Configuration Name=\"%s\"", $sizeData));
	my $configData = OpsB::Common::FindLineWithKey($version_data, $key);

	my ($doCompare, $singleCpu, $GWCPU, $DPSCPU, $singleMem, $GWMem, $DPSMem) = (false, "", "", "", "", "", "");

	if (length($configData) == 0) {
		WO($MSG_BadConfig, M_WARN);
		$doCompare = false;
	}
	else {
		$singleCpu = OpsB::Common::GetAttributeFromData($configData, "SingleCPU");
		$GWCPU = OpsB::Common::GetAttributeFromData($configData, "GWCPU");
		$DPSCPU = OpsB::Common::GetAttributeFromData($configData, "DPSCPU");
		$singleMem = OpsB::Common::GetAttributeFromData($configData, "SingleMemory");
		$GWMem = OpsB::Common::GetAttributeFromData($configData, "GWMemory");
		$DPSMem = OpsB::Common::GetAttributeFromData($configData, "DPSMemory");
		$doCompare = true;
	}

	#
	# Now get the data for harcdware
	#

	$query = "select MACHINE_NAME, NUM_OF_CPU, MEMORY, INSTALL_TYPE from DEPLOY_HW";
	my $hwData = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DBMgmt, $ARG_DBType, $ARG_SID, ";"); # Use semi colon as all in one server has GW,DPS

	if (length($hwData) == 0) {
		#
		# Something went wrong here as this informationmust be present
		#

		WO($MSG_NoSize, M_ERROR);
		return;
	}	

	foreach my $line((split(/\n/, $hwData))) {
		my @serverData = split(/;/, $line);
		my ($serverName, $cpuCount, $memSizeMB, $serverType) = ($serverData[0], $serverData[1], $serverData[2], $serverData[3]);
		if (index($serverType, ",") > 0) {$serverType = "Single";}

		#
		# Convert Memory to GB from MBg
		#

		my $memSizeGB = ($memSizeMB / 1024);

		my $sev = M_OK;

		if ($doCompare == false) {
			$sev = M_INFO;
			$msg = sprintf($MSG_ServerInfo, $serverType, $serverName, $cpuCount, int($memSizeGB));
		}
		else {
			my ($memCheck, $CPUCheck) = ($singleMem, $singleCpu);
			if ($serverType =~ /DPS/i) {($memCheck, $CPUCheck) = ($DPSMem, $DPSCPU);}
			if ($serverType =~ /GW/i) {($memCheck, $CPUCheck) = ($GWMem, $GWCPU);}

			if (($cpuCount < $CPUCheck) || ($memSizeGB < $memCheck)) {
				$sev = M_WARN;
			}

			$msg = sprintf($MSG_ServerInfo_Check, $serverType, $serverName, $cpuCount, int($memSizeGB), $CPUCheck, $memCheck);
		}

		WO($msg, $sev);
	}

	WO("DoMgmtChecks: End", M_DEBUG);
}

#
# The checks on the event database
#

sub DoEventChecks() {
	WO("DoEventChecks: Start", M_DEBUG);
	my $msg = "";
	
	if ($ARG_NoWelcome == false) {
		WO(sprintf($MSG_Event_Checks, $ARG_DBEvent), M_INFO);
	}

	#
	# Run a test query - sinze a return of no data is valid here if no ETI rules are custom
	#
	
	my $query = "select NAME from C001_MAPPING_RULES";
	my $dummy = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DBEvent, $ARG_DBType, $ARG_SID);
	
	if (length($dummy) == 0) {
		return;	# Some issue which will be shown by the call
	}

	$query = "select NAME, DESCRIPTION from C001_MAPPING_RULES where ARTIFACT_ORIGIN = 'CUSTOM'";
	my $custom = OpsB::Database::SimpleQuery($query, $ARG_Server, $ARG_Port, $ARG_User, $ARG_PWD, $ARG_DBEvent, $ARG_DBType, $ARG_SID);

	if (length($custom) > 0) {
		#
		# Reformat this information
		#
		
		if ($ARG_ETI_Detail == true) {
			my $reformatted = "\n";
			
			foreach my $line((split(/\n/, $custom))) {
				my @items = split(/,/, $line);
				my $name = "\t" . $items[0];	# For formatting
				
				#
				# The description may have commas or be empty
				#
				
				my $description = join(",", @items[1..$#items]);
				
				if (length($description) > 0 ) {
					$name .= sprintf(" (%s)", $description);
				}
				
				$reformatted .= sprintf("\n%s", $name);
			}
			
			$msg = sprintf($MSG_ETI_Mapping_Custom, $reformatted);
		}
		else {
			#
			# Just a count of the ETI mapping rules
			#

			my $num = scalar(split(/\n/, $custom));
			$msg = sprintf($MSG_ETI_Mapping_Custom_Summary, $num);
		}

		WO($msg, M_NOTE);
	}
	
	
	WO("DoEventChecks: End", M_DEBUG);
} #DoEventChecks

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
	
	$ARG_Server = OpsB::Common::FindArg("server");
	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_PWD = OpsB::Common::FindArg("pwd");
	$ARG_Port = OpsB::Common::FindArg("port");
	$ARG_DBEvent = OpsB::Common::FindArg("dbevent");
	$ARG_DBMgmt = OpsB::Common::FindArg("dbmgmt");
	$ARG_DBType = OpsB::Common::FindArg("dbtype");
	$ARG_SID = OpsB::Common::FindArg("sid");
	$ARG_ETI_Detail = OpsB::Common::FindSwitch("etidetail");
	$ARG_DBRTSM = OpsB::Common::FindArg("dbrtsm");
	
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
	
	if (length($ARG_User) ==0) {
		$ARG_Trusted = true;
		$ARG_PWD = "";
	}
	
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
	
	OpsB::Common::CommonHelp();

	#our $scriptArgs = "user,pwd,server,port,sid,dbevent,dbtype,trusted,dbmgmt,etidetail,dbrtsm";

	WO("  -server <server>\tThe Database server");
	WO("  -port <port>\t\tThe port the database server is listening on (the default depends on the server type)");
	WO("  -user <user>\t\tThe user id to connect with");
	WO("  -pwd <password>\tThe user password");
	WO("  -trusted\t\tSwitch - valid for SQL on Windows only. Use Current Windows credentials to connect to database");
	WO("  -sid <SID>\t\tFor Oracle only, the database SID");
	WO(sprintf("  -dbtype <TYPE>\tThe database type (%s, %s or %s)", $DBType_MSSQL_Input, OpsB::Database::DBTYPE_Oracle_String, OpsB::Database::DBTYPE_PG_String));
	WO("  -dbmgmt <NAME>\tDatabase name for the management database");
	WO("  -dbevent <NAME>\tDatabase name for the event database");
	WO("  -dbrtsm <NAME>\tDatabase name for the UCMDB database");
	WO("  -etidetail\t\tSwitch, when specified then the names of any Indicator Mapping custom rules will be displauyed");

	WO("");
	WO("If a database name is specified (ie \"-dbmgmt mgmt\") then various checks for that database will be made. For the databases not specified,");
	WO("that database is ignored");
}

#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();