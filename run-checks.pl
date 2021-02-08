#!/usr/bin/perl

# ++
# File:     		run-checks.pl
# Created:  		20-Aug-2020, by Andy
# Reason:   		wrapper script for db tools scripts
# --
# Abstract: 		Run this script to driver db-server-checker.pl and obm-server-checks.pl
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	20-Aug-2020	Created
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
use OpsB::HPBSM;
use OpsB::HPBSM qw(TopazDir HP_BSM_MODULE_VERSION $Java);
use OpsB::Database;
use OpsB::Database qw(DATABASE_MODULE_VERSION $DBTYPE_MSSQL $DBTYPE_Oracle $DBTYPE_PG);

our $Topaz = TopazDir();
#
# required
#

our $scriptVersion = "2.2";
our $scriptArgs = "ignore,nodb,nosys,server,port,db,user,pwd,sid,trusted,set,trusted,size,dbtype,force,showok,frag,type,nodisk,nomem";

our ($useSettings, $settingsData, $settingsError) = (false, "", "");
our $settingsFile = OpsB::Common::GetScriptDir($0) . "settings.dat";
if (-e $settingsFile) {($useSettings, $settingsData, $settingsError) = OpsB::Common::ReadFileToString($settingsFile);}

our $OBMVersion = "";

if ($useSettings == true) {
		my $line = OpsB::Common::FindLineWithKey($settingsData, "<VersionInfo OBM");
		$OBMVersion = OpsB::Common::GetAttributeFromData($line, "Version");
}

our $DBType_MSSQL_Input = OpsB::Database::DBTYPE_MSSQL_String;
$DBType_MSSQL_Input =~ s/ //g; # Do this to remove spaces from "MS SQL" to make the input easier - MSSQL

our %configData = ();

our $Size_Small = "Small";
our $Size_Medium = "Medium";
our $Size_Large = "Large";

our $Type_DPS = "DPS";
our $Type_GW = "Gateway";
our $Type_All = "All";

#
# For passing to the system checker
#

our $BSMHome = "";
our $BSMInstall = "";
our $BSMData = "";
our $temp = "";

#
# As we use this in varios places, do at the start#
#

our ($My_Name, $My_OS, $My_Architecture, $My_OSVersion) = OpsB::Common::GetHostInfo();

#
# Messages
#

our $MSG_NoUser_DisableChecks = "No database user was provided, database checks will be disabled";
our $MSG_NoTrusted_DisableChecks = "Trusted connection is only suppored on Windows with MS SQL, database checks will be disabled";
our $MSG_DBTypeUnsupported_DisableChecks = "The specified database type is not supported - database checks will be disabled";
our $MSG_IgnoreConfig = "The OBM Configuration information will be ignored";
our $MSG_OBMFound = "Operations Bridge is installed on this server";
our $MSG_OBMConfigFailed_DisableChecks = "Unable to continue using the configuration information, databse checks disabled";
our $MSG_MustChooseSomething = "\tBoth \"-nosys\" and \"-nodb\" specified - this disables all checks";
our $MSG_InvalidSize = sprintf("\tAn invalid configuration size (%s) was specified. It must be one of \"%s\", \"%s\" or \"%s\"", "%s", $Size_Small, $Size_Medium, $Size_Large);
our $MSG_InvalidType = sprintf("\tAn invalid server type (%s) was specified. It must be one of \"%s\", \"%s\" or \"%s\"", "%s", $Type_All, $Type_DPS, $Type_GW);
our $MSG_NoPassword = "\tNo password provided for database access";
our $MSG_DBType_Prompt = "Specify the Database Type for Server \"%s\" (%s=%s, %s=%s, %s=%s)";
our $MSG_DBType_Invalid = sprintf("\tThe -dbtype %s is invalid, it must be a value between 1 and 3 or one of \"%s\", \"%s\" or \"%s\"", "%s", $DBType_MSSQL_Input, OpsB::Database::DBTYPE_Oracle_String, OpsB::Database::DBTYPE_PG_String);

#
# Script Specific Arguments
#

our $ARG_IgnoreConfig = false;
our $ARG_NoDB = false;
our $ARG_NoSys = false;

#
# For db checks script
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
# For Server checks
#

our $ARG_ServerType = "";
#our $ARG_Size = ""; # Already defined above
our $ARG_NoDisk = false;
our $ARG_NoMem = false;

#
# The other scripts we will run
#

our $dbCheck = 1;
our $sysCheck = 2;
our @Utilities = ("db-server-checks.pl:Database Server checks:1", "obm-server-checks.pl:OBM Server system checks:2");


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
	
	my $additionalModules = sprintf("BSM Module Version: %s, Database Module Version: %s", HP_BSM_MODULE_VERSION, DATABASE_MODULE_VERSION);
	my $description = "Run database and server checks in preparation for installation or upgrade of OpsBridge to Version $OBMVersion";
	my $title = "Operations Bridge Database Toolkit";
	OpsB::Common::SayHello($scriptVersion, $additionalModules, $description, $title); # ScriptVersion, AdditionalModules, Specific Description 
	
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
	
	if (length($Topaz) > 0) {
		WO($MSG_OBMFound, M_INFO);
		
		if ($ARG_IgnoreConfig == false) {
			%configData = OpsB::HPBSM::ReadTopazInfra();
			
			if ($configData{"OK"} == false) {
				
				if ($ARG_NoDB == false) {
					WO($MSG_OBMConfigFailed_DisableChecks, M_WARN);
					$ARG_NoDB = true;
				}

			}
			
			#
			# Set the arguments based on the configuration - allow override of the user and the port if those are provided, use the config for everything else
			#
			
			if (defined $configData{"ManagementDb.dbType"}) {
				$ARG_DBType = $configData{"ManagementDb.dbType"};
				
				#
				# Convert to the correct string
				#
				
				$ARG_DBType =~ s/ //g;	# MS SQL needs to be MSSQL
			}
			else {
				$ARG_DBType = "";
			}
			
			if (defined $configData{"ManagementDb.dbSID"}) {
				$ARG_SID = $configData{"ManagementDb.dbSID"};
			}
			else {
				$ARG_SID = "";
			}
			
			if (defined $configData{"ManagementDb.dbHost"}) {
				$ARG_Server = $configData{"ManagementDb.dbHost"};
			}
			else {
				$ARG_Server = "";
			}
			
			if (defined $configData{"ManagementDb.dbName"}) {
				$ARG_DB = $configData{"ManagementDb.dbName"};
			}
			else {
				$ARG_DB = "";
			}
			
			if ((length($ARG_Port) == 0) && (defined $configData{"ManagementDb.dbPort"})) {
				$ARG_Port = $configData{"ManagementDb.dbPort"};
			}
			
			if ((length($ARG_User) == 0) && ($ARG_Trusted == false) && (defined $configData{"ManagementDb.dbUser"})) {
				$ARG_User = $configData{"ManagementDb.dbUser"};
			}
			
			#foreach my $key(keys %configData) {
			#	my $value = $configData{$key};
			#	WO("Key: $key, value: $value");
			#}
			
			#
			# Get the BSM directories we need for some of the checks
			#
			
			my %BSM = OpsB::HPBSM::GetBSMLocations();
			
			if ($BSM{"OK"} == true) {
				($BSMHome, $BSMInstall, $BSMData, $temp) = ($BSM{"BSMHome"}, $BSM{"BSMInstall"}, $BSM{"BSMData"}, $BSM{"temp"});				
			}
			
		}
		else {
			WO($MSG_IgnoreConfig, M_INFO);
		}	
				
	}
	
	if ($ARG_NoDB == false) {
		my ($ok, $error) = (true, "");
		
		if ($ARG_NoDB == false) {
			#
			# Make sure that we have the DB information we will need
			#
			
			if (length($ARG_Server) == 0) {
				$ARG_Server = $My_Name;
			}
			
			if (length($ARG_DBType) == 0) {
				#
				# Must have this so prompt for it
				#
				
				my $answer = OpsB::Common::GetAnswer(sprintf($MSG_DBType_Prompt, $ARG_Server, $DBTYPE_MSSQL, OpsB::Database::DBTYPE_MSSQL_String, $DBTYPE_Oracle, OpsB::Database::DBTYPE_Oracle_String, $DBTYPE_PG, OpsB::Database::DBTYPE_PG_String));
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
	
			if ($ok == false) {
				WO($error, M_WARN);
				$ARG_NoDB = true;
			}

		}

		if (($ARG_DBType ne OpsB::Database::DBTYPE_MSSQL_String) && ($ARG_DBType ne OpsB::Database::DBTYPE_Oracle_String) && ($ARG_DBType ne OpsB::Database::DBTYPE_PG_String)) {
			WO($MSG_DBTypeUnsupported_DisableChecks, M_WARN);
			$ARG_NoDB = true;
		}
		else {
			$ARG_DBType =~ s/ //g;	# MS SQL to MSSQL
		}
		
		if ($ARG_NoDB == false) {
			
			if ($ARG_Trusted == true) {
				#
				# Doesn't work unless on Windows and for SQL
				#
				
				if (($IsWindows == false) || ($ARG_DBType eq OpsB::Database::DBTYPE_Oracle_String) || ($ARG_DBType eq OpsB::Database::DBTYPE_PG_String)) {
					WO($MSG_NoTrusted_DisableChecks, M_WARN);
					$ARG_NoDB = true;
				}
				
			}
			else {
				
				if (length($ARG_User) == 0) {
					WO($MSG_NoUser_DisableChecks, M_WARN);
					$ARG_NoDB = true;
				}
				
			}
		
		}
		
	} # final db checks
	
	for my $utilityData(@Utilities) {
		my @array = split(/:/, $utilityData);
		my($script, $description, $type) = ($array[0], $array[1], $array[2]);
		
		#WO("Script: $script, $description, $type");
		
		if (($type == $dbCheck && $ARG_NoDB == false) || ($type == $sysCheck && $ARG_NoSys == false)) {
			$script = OpsB::Common::GetScriptDir($0) . $script;
			RunScript($script, $description);
		}
		
	}
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Run the script
#

sub RunScript() {
	my ($script, $description) = @_;
	
	WO("RunScript: End", M_DEBUG);
	
	my $args = "-nowelcome -timeout $ARG_Timeout";
	
	if ($ARG_Debug == true) {$args .= " -debug";}
	if ($ARG_Log == true) {$args .= " -log";}
	if ($ARG_Color == false) {$args .= " -nocolor";}
	if ($ARG_Quiet == true) {$args .= " -quiet";}
	
	if ($script =~ /db-server-checks/i) {
		
		if (length($ARG_Server) > 0) {
			$args .= " -server \"$ARG_Server\"";
		}
		
		if (length($ARG_PWD) > 0) {
			$args .= " -pwd \"$ARG_PWD\"";
		}
		
		if (length($ARG_DB) > 0) {
			$args .= " -db \"$ARG_DB\"";
		}
		
		if (length($ARG_Port) > 0) {
			$args .= " -port $ARG_Port";
		}
				
		if (length($ARG_User) > 0) {
			$args .= " -user \"$ARG_User\"";
		}
		
		if ($ARG_Trusted == true) {
			$args .= " -trusted";
		}
		
		if (length($ARG_SID) > 0) {
			$args .= " -sid \"$ARG_SID\"";
		}		
		
		if (length($ARG_DBType) > 0) {
			$args .= " -dbtype \"$ARG_DBType\"";
		}		

		if (length($ARG_Size) > 0) {
			$args .= " -size \"$ARG_Size\"";
		}

		if (length($ARG_Frag) > 0) {
			$args .= " -frag \"$ARG_Frag\"";
		}

		if ($ARG_Set == true) {
			$args .= " -set";
		}

		if ($ARG_Force == true) {
			$args .= " -force";
		}

		if ($ARG_ShowOK == true) {
			$args .= " -showok";
		}

	}

	
	if ($script =~ /obm-server-checks/i) {
		
		if (length($ARG_Size) > 0) {
			$args .= " -size \"$ARG_Size\"";
		}

		if (length($ARG_ServerType) > 0) {
			$args .= " -type \"$ARG_ServerType\"";
		}
		
		if ($ARG_NoDisk == true) {
			$args .= " -nodisk";
		}		
		
		if ($ARG_NoMem == true) {
			$args .= " -nomem";
		}
		
		if (length($BSMHome) > 0) {
			#
			# Add directory overrides
			#
			
			$args .= " -home \"$BSMHome\"";
			$args .= " -install \"$BSMInstall\"";
			$args .= " -data \"$BSMData\"";
			$args .= " -temp \"$temp\"";
		}
		
	}
		
	#WO("");
	WO("Performing $description ...", M_INFO);
	#WO("");
	##WO("$script");
	#WO("==> $args");
	
	my $runOK = OpsB::Common::RunPerlScript($script, $args);

	WO("");
	#WO("**** Finished running script for $description ... ", M_INFO);

	WO("RunScript: End", M_DEBUG);
}
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
	
	$ARG_IgnoreConfig = OpsB::Common::FindSwitch("ignore");
	$ARG_NoDB = OpsB::Common::FindSwitch("nodb");
	$ARG_NoSys = OpsB::Common::FindSwitch("nosys");
	
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
	
	$ARG_ServerType = OpsB::Common::FindArg("type");
	#$ARG_Size = OpsB::Common::FindArg("size");
	$ARG_NoDisk = OpsB::Common::FindSwitch("nodisk");
	$ARG_NoMem = OpsB::Common::FindSwitch("nomem");	
	
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
	
	#
	# Make type  "all" if undefined or "wrong"
	#
	
	if (length($ARG_ServerType) == 0) {
		$ARG_ServerType = $Type_All;
	}
	
	if (lc $ARG_ServerType eq lc substr($Type_All, 0, length($ARG_ServerType))) {$ARG_ServerType = $Type_All;}
	if (lc $ARG_ServerType eq lc substr($Type_DPS, 0, length($ARG_ServerType))) {$ARG_ServerType = $Type_DPS;}
	if (lc $ARG_ServerType eq lc substr($Type_GW, 0, length($ARG_ServerType))) {$ARG_ServerType = $Type_GW;}

	if (($ARG_ServerType ne $Type_All) && ($ARG_ServerType ne $Type_DPS) && ($ARG_ServerType ne $Type_GW)) {
		$error = OpsB::Common::AddString($error, (sprintf($MSG_InvalidType, $ARG_ServerType)), "\n");
		$ok = false;
	}

	if ($ARG_NoMem == true && $ARG_NoDisk == true) {
		#
		# don;t do system checks
		#
		
		$ARG_NoSys = true;
	}
	
	if ($ARG_Trusted == false && length($ARG_PWD) == 0 && $ARG_NoDB == false) {
		$error = OpsB::Common::AddString($error, $MSG_NoPassword, "\n");
		$ok = false;
	}

	if ($ARG_NoDB == true && $ARG_NoSys == true) {
		$error = OpsB::Common::AddString($error, $MSG_MustChooseSomething, "\n");
		$ok = false;
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
	
	WO("Generic inputs");
	WO("");
	WO("  -ignore\t\tWhen running on a server with OpsBridge components installed, ignore the existing configuration");
	WO("  -nodb\t\t\tDo not perform Database Server checks");
	WO("  -nosys\t\tDo not perform system checks");
	WO(sprintf("  -size <size>\t\tUse this argument to specify the configuration size for checks (must be one of \"%s\", \"%s\" or \"%s\")", $Size_Small, $Size_Medium, $Size_Large));

	WO("");
	WO("Database check inputs");
	WO("");
	WO("  -server <server>\tHost name (or Host and instance) of the database server. Localhost will be used if this is not supplied");
	WO("  -port <port>\t\tTCPIP port for server connection (optional)");
	WO("  -user <user>\t\tDatabase server login");
	WO("  -pwd <password>\tPassword for database user");
	WO("  -sid <SID>\t\tRequired for Oracle connection");
	WO("  -trusted\t\tFor SQL Server when the script runs on Windows - use Windows authentication");
	WO(sprintf("  -dbtype <type>\tThe database type (must be \"%s\", \"%s\" or \"%s\")", OpsB::Database::DBTYPE_Oracle_String, OpsB::Database::DBTYPE_PG_String, $DBType_MSSQL_Input));
	WO("  -set\t\t\tUse this switch to commit changes if necessary");
	WO("  -force\t\tUse this switch to disable prompts if changes are necessary");
	WO("  -frag <percent>\tFragmentation percent threshold for checking database indexes. Default is 30");	
	
	WO("");
	WO("System check inputs");
	WO("");
	WO(sprintf("  -type <type>\t\tRole the server will have (one of \"%s\", \"%s\" or \"%s\")", $Type_All, $Type_DPS, $Type_GW)); 
	WO("  -nodisk\t\tDisable disk checks");
	WO("  -nomem\t\tDisable memory checks");
	
	OpsB::Common::CommonHelp();
	
	WO("Examples");

	my $invoke = OpsB::Common::GetRunningScriptName();
	if ($IsWindows == true) {$invoke = sprintf("perl %s", $invoke);} else {$invoke = sprintf("./%s", $invoke);}

	WO("");	
	WO("        $invoke -server MYSERVER -user postgres -pwd P\@ssw0rd -dbtype postgres");
	WO("");
	WO("  This will invoke the script run database checks on the Postgres server MYSERVER. Note that the dbtype can be specified as a partial");
	WO("  name (ie \"p\" for Postgresql). This check will be made for a \"small\" configuration and for a server with all roles.");

	WO("");	
	WO("        $invoke -trusted -dbtype ms -type dps -size large");
	WO("");
	WO("  This will invoke the script run database checks on the local system. Note that the dbtype can be specified as a partial name");
	WO("  (ie \"ms\" for MSSQL). This check will be made for a \"large\" configuration and for a server with the DPS role. As with the");
	WO("  parameter \"-dbtype\", the \"-size\" and \"-type\" parameters can be partial (ie \"l\" for large and \"d\" for DPS)");
	
	WO("");	
	WO("        $invoke -pwd P\@ssw0rd");
	WO("");
	WO("  This will invoke the script run database checks using the configuration information found on the local server, assuming the local server");
	WO("  has either the DPS or Gateway role already installed. In this case, the database information is read from the configuration and only the");
	WO("  password is required.");
	
	WO("");

}
#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();