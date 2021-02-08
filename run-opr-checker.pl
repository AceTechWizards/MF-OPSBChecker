#!/usr/bin/perl

# ++
# File:     	run-opr-checker.pl
# Created:  	18-May-2020, by Andy
# Reason:   	V2 of the tool - cleaned up and improved code
# --
# Abstract: 	Run the opr-chekcker utility
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	18-May-2020	Refresh for V2
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

use OpsB::Checker;

use OpsB::Database;
use OpsB::Database qw(DATABASE_MODULE_VERSION);

our $HPBSM_Module_Version = OpsB::HPBSM::HP_BSM_MODULE_VERSION;

#
# required
#

our $scriptVersion = "2020.12.14";
our $scriptArgs = "input,pwd,forcedb,user,port,forcetls,trusted";

#
# Messages
#

our $MSG_CheckerCommandReturnedNothing = "No information was returned from the command to retrieve OBM information";
our $MSG_ReadLogError = "Failed to process the OBM information - %s";
our $MSG_HostInformation = "OMi/OBM Server: %s, O/S: %s (%s) with %s memory";
our $MSG_OBMVersion = "Detected OMi/OBM Version: %s build %s (patch %s)";
our $MSG_OBMVersionNoPatch = "Detected OMi/OBM Version: %s build %s";
our $MSG_CoreServer = "Core Server: %s (url: %s)";
our $MSG_NoCoreServer = "Unable to detect core server url (check that opr-checker was executed with the -sys and -opr switches)";
our $MSG_CoreAndCenterServer = "Core/Center Server: %s (url: %s)";
our $MSG_CenterServer = "Center Server: %s (url %s)";
our $MSG_Roles = "Server Roles: %s";
our $MSG_MGMTDatabase = "%s Database - %s server %s (port %s). Database Name: %s, user: %s";
our $MSG_MGMTDatabaseOra = "%s Database - %s server %s (SID %s, port %s). Database Name: %s, user: %s";
our $MSG_NoChecks = "The file %s was not found - version checks cannot be completed";
our $MSG_NoDBInfo = "Unable to determine %s Database information";
our $MSG_ServerVersion = "Database server version: %s";
our $MSG_DBServerLow = "The %s database version %s is no longer supported for OBM version %s. It should be upgraded to version %s";
our $MSG_DBServerOK = "The %s database version %s is supported for OBM version %s";
our $MSG_ETI_Checks = "Checking for Indicator Mapping Rules custom definitions...";
our $MSG_ConfigChecks = "Checking for DPS/Gateway server configurations...";
our $MSG_UCMDB_Checks = "Checking UCMDB Content Packs ...";

#
# Script Specific Arguments
#

our $ARG_Input = "";
our $ARG_DBPWD = "";
our $ARG_DODB = false;
our $ARG_User = "";
our $ARG_Port = "";
our $ARG_ForceTLS = false;
our $DO_DB = false;
our $ARG_Trusted = false;

our $ThisVersion = "";
our $ThisVersionExternal = "";

#
# For version information
#

our ($useVersion, $version_data, $versionError) = (false, "", "");
our $versionsFile = OpsB::Common::GetScriptDir($0) . OpsB::Common::VERSIONS_FILE;
if (-e $versionsFile) {($useVersion, $version_data, $versionError) = OpsB::Common::ReadFileToString($versionsFile);}

#
# Database checks
#

our $dbChecksFile = OpsB::Common::GetScriptDir($0) . "database-checks.pl";

our $perl = "perl";
our $tlsUtil = OpsB::Common::GetScriptDir($0) . "tls-check.pl";
if (!(-e $tlsUtil)) {$tlsUtil = "";}

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
	# Show banner
	#
	
	my $additionalModules = sprintf("Checker Version: %s, HPBSM Version: %s, Database Version: %s", OpsB::Checker::CHECKER_MODULE_VERSION, $HPBSM_Module_Version, OpsB::Database::DATABASE_MODULE_VERSION); # sprintf("DB Version: %s, XYZ Version: %s", $modDB_Version, $modXYZ_Version);
	OpsB::Common::SayHello($scriptVersion, $additionalModules, "This script invokes opr-checker to retrieve OBM related information"); # ScriptVersion, AdditionalModules, Specific Description 
	
	#
	# Show the inputs  - set $argValues to the list from this sccript, the generic ones will be added in the common module. For example
	#
	# my $argValues = sprintf("\n\t-xyz = %s\n\t-abc = %s\n", $ARG_XYZ, $ARG_ABC);
	#
	
	my $argValues = "";	
	OpsB::Common::ShowInputs($argValues);
		
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
	# If we were asked to do Database things, but we don;t know where Java is - we should disable that here and say why
	#
	
	if ($DO_DB == true) {
		
		if (length($Java) == 0) {
			our $MSG_NoJava = "Java is not installed or could not be detected. Database checks rely on Java and will be disabled";
			WO($MSG_NoJava, M_WARN);
			$DO_DB = false;
		}
	}
	
	#
	# Get the version we are aiming for
	#
	
	if ($useVersion == true) {
		my $info = OpsB::Common::FindLineWithKey($version_data, "<Main Version=");
		
		if (length($info) > 0) {
			$ThisVersion = OpsB::Common::GetAttributeFromData($info, "InternalVersion");
			$ThisVersionExternal = OpsB::Common::GetAttributeFromData($info, "Version");
		}
		
	}
	
	my ($data, $msg) = ("", "");
	
	if (length($ARG_Input) > 0) {
		#
		# Read the pre-prepared file
		#
		
		$msg = sprintf(OpsB::Common::MSG_ReadFromInput, $ARG_Input);
		WO($msg, M_DEBUG);
		
		my ($readOK, $readError) = (true, "");
		($readOK, $data, $readError) = OpsB::Common::ReadFileToString($ARG_Input);
	}
	else {
		#
		# Get the HPBSM directory and quit if not found
		#
				
		my ($installed, $topaz) = TopazDir();
		
		if ($installed == false) {
			WO(OpsB::Common::MSG_TopazMissing, M_FATAL);
			return;
		}
		
		#
		# Now get and check the utility
		#
		
		my $util = $topaz . OpsB::Checker::opr_checker_Unix;
		if ($IsWindows == true) {$util = $topaz . OpsB::Checker::opr_checker_Win;}
		
		if (-e $util) {
			#
			# Run the utility
			#
			
			my $cmd = sprintf("\"%s\" -rapid -sys -opr -security", $util);	# security required for ldap
			my ($cmdOK, $rc, $stdout, $stderr) = OpsB::Common::RunCommandTimeout($cmd, "OBM checker utility");
			
			if (($cmdOK == false) || ($rc != 0)) {
				#
				# If the timeout happened then we already dealt with messages - see if there is data despite that message
				#
				
				if ($rc == OpsB::Common::CMD_TimeoutCode) {
					$data = $stdout;
				}
				else {
					$msg = sprintf(OpsB::Common::MSG_CommandFailed, $rc, $stderr);
					WO($msg, M_FATAL);
				}
			}
			else {
				#
				# Command OK, but check ther was some output
				#

				if (length($stdout) > 0) {
					$data = $stdout;
				}
				else {
					#
					# We were expecting something...
					#
					
					WO($MSG_CheckerCommandReturnedNothing, M_ERROR);
				}
				
			} # Command OK			
			
		} # No utility
		else {
			$msg = sprintf(OpsB::Common::MSG_UtilMissing, $util);
			WO($msg, M_FATAL);
		}
					
	} # Input file
	
	#
	# If something failed then $data is empty so stop here. Any errors having already been generated
	#
	
	if (length($data) > 0) {
		ProcessData($data);
	}		
	
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Process the data we have from the command or the input file
#

sub ProcessData() {
	my $data = shift;
	WO("ProcessData: Start", M_DEBUG);
	
	my ($msg, $sev) = ("", M_INFO);
	
	#
	# Need to know if this is a UNIX or a Windows output as they are different. Clearly f running "online" the type matches the system, but if "offline" the output
	# might have been grabbed form a Unix box but the script running on Windows.
	#
	
	my $logTypeUnix = true;
	
	if (length($ARG_Input) == 0) {
		#
		# Running online so the OS runing the script matches the log data
		#
		
		if ($IsWindows == true) {$logTypeUnix = false;}
	}
	else {
		$logTypeUnix = OpsB::Checker::LogIsUnix($data);
	}
	
	WO(sprintf("Log type Unix: %s", $logTypeUnix), M_DEBUG);
	
	my ($obmOK, $obmVersion, $obmBuild, $obmPatch, $obmError) = OpsB::Checker::GetOBMInformation($data, $logTypeUnix);
	
	if ($obmOK == false) {
		my $msg = sprintf($MSG_ReadLogError, $obmError);
		WO($msg, M_FATAL);
		return;
	}
	
	WO(sprintf("Returned from OBM check:\n\tVersion: %s\n\tBuild: %s\n\tPatch: %s", $obmVersion, $obmBuild, $obmPatch), M_DEBUG);

	#
	# Show the OS information we picked up from the log
	#
		
	my ($logHost, $logOS, $logMem) = OpsB::Checker::GetHostInformation($data, $logTypeUnix);
	$logMem = OpsB::Common::MakeGB($logMem);
	
	my $osName = "Unix";
	if ($logTypeUnix == false) {$osName = "Windows";}
	
	$msg = sprintf($MSG_HostInformation, $logHost, $osName, $logOS, $logMem);
	WO($msg, M_INFO);
	
	#
	# Show what we found
	#
	
	#
	# Get the patch number when processing the message information#
	#
	
	my $installedIP = "";
	
	$msg = sprintf($MSG_OBMVersionNoPatch, $obmVersion, $obmBuild);
	
	if (length($obmPatch) > 0) {
		$msg = sprintf($MSG_OBMVersion, $obmVersion, $obmBuild, $obmPatch);
		$installedIP = OpsB::Common::GetIPNumber($obmPatch);
		
		WO(sprintf("OBM Patch: %s", $installedIP), M_DEBUG);
	}
	
	WO($msg, M_INFO);
	
	#
	# Core Server check
	#
	
	my ($coreHost, $coreUrl) = OpsB::Checker::GetCoreServerInformation($data);
	
	$msg = sprintf($MSG_CoreServer, $coreHost, $coreUrl);
	
	if (length($coreHost) == 0) {
		$msg = $MSG_NoCoreServer;
		$sev = M_DEBUG;
	}
	
	#
	# Center servers check
	#

	my ($centerHost, $centerUrl) = OpsB::Checker::GetCentersServerInformation($data);
	
	if (length($centerHost) > 0) {
		$sev = M_INFO;
		#
		# See if it is the same as the core server
		#
		
		if ((lc $coreHost eq lc $centerHost) && (lc $coreUrl eq lc $centerUrl)) {
			#
			# Same so reduce messages
			#
			
			$msg = sprintf($MSG_CoreAndCenterServer, $coreHost, $coreUrl);
		}
		else {
			#
			# Different so show the core server message before building the Center server message
			#
						
			WO($msg, M_INFO);
			$msg = sprintf($MSG_CenterServer, $centerHost, $centerUrl);			
		}
		
	}
	
	WO($msg, $sev);
	
	#
	# Check Server roles
	#
	
	my ($isGW, $isDPS, $isApache) = OpsB::Checker::GetServerRoles($data, $logTypeUnix);
	
	if (($isGW == true) || ($isDPS == true) || ($isApache == true)) {
		#
		# At least one role discovered
		#
		
		my $roles = "";
		
		if ($isGW == true) {$roles = "Gateway Server";}
		if ($isDPS == true) {$roles = OpsB::Common::AddString($roles, "Data Processing Server", ", ");}
		if ($isApache == true) {$roles = OpsB::Common::AddString($roles, "Apache Server", ", ");}
		
		$msg = sprintf($MSG_Roles, $roles);
		WO($msg, M_INFO);
	}
	
	#
	# Get Database information
	#

	my $online = false;
	if (length($ARG_Input) ==0) {$online = true;}
	
	my %DBInfo = OpsB::Checker::GetMgmtDBInfo($data, $logTypeUnix, $online);
	
	$sev = M_INFO;
	my $mgmtdbOK = true;
	
	if ((defined $DBInfo{"Host"}) && (length($DBInfo{"Host"}) > 0)){
		$msg = sprintf($MSG_MGMTDatabase, "Management", $DBInfo{"DBType"}, $DBInfo{"Host"}, $DBInfo{"Port"}, $DBInfo{"Database"}, $DBInfo{"User"});
		
		if ((defined $DBInfo{"SID"}) && (length($DBInfo{"SID"}) > 0)) {
			$msg = sprintf($MSG_MGMTDatabaseOra, "Management", $DBInfo{"DBType"}, $DBInfo{"Host"}, $DBInfo{"SID"}, $DBInfo{"Port"}, $DBInfo{"Database"}, $DBInfo{"User"});
		}
		
	}
	else {
		$msg = sprintf($MSG_NoDBInfo, "Management");
		$sev = M_WARN;
		$mgmtdbOK = false;
	}
	
	WO($msg, $sev);

	if ($sev == M_INFO) {
		#
		# Get DB Server version information. Sets $DO_DB to fals on failed#

		GetDBServerInfo(%DBInfo);

		#
		# Invoke using the databse script to get some additional checks in the databse (mgmt)
		#

		if (-e $dbChecksFile && $DO_DB == true) {
			my ($mServer, $mUser, $mPWD, $mDB, $mPort, $mSID, $mType) = ("", "", "", "", "", "", "");

			$mServer = $DBInfo{"Host"};
			$mDB = $DBInfo{"Database"};
			$mType = $DBInfo{"DBType"};

			if (defined $DBInfo{"User"}) {$mUser = $DBInfo{"User"}};
			if (defined $ARG_DBPWD) {$mPWD = $ARG_DBPWD};
			if (defined $DBInfo{"Port"}) {$mPort = $DBInfo{"Port"}};
			if (defined $DBInfo{"SID"}) {$mSID = $DBInfo{"SID"}};

			#
			# Override the port if required
			#

			if (length($ARG_Port) > 0) {
				$mPort = $ARG_Port;
			}

			#
			# Override the user if asked
			#

			if (length($ARG_User) > 0) {
				$mUser = $ARG_User;
			}

			#
			# If "Trusted"
			#

			if ($ARG_Trusted == true) {
				$mUser = "";
				$mPWD = "";
			}

			my $args = sprintf("-nowelcome -server \"%s\" -user \"%s\" -pwd \"%s\" -port \"%s\" -dbmgmt %s -dbtype %s -sid \"%s\"", $mServer, $mUser, $mPWD, $mPort, $mDB, $mType, $mSID);
			if ($ARG_Debug == true) {$args .= " -debug";}
			if ($ARG_Trusted == true) {$args .= " -trusted"; }

			#
			# Run the database checks
			#

			WO($MSG_ConfigChecks, M_INFO);
			my $runOK = OpsB::Common::RunPerlScript($dbChecksFile, $args);	
		}

	}
	
	#
	# Event database
	#
	
	my $eventDBKey = "opr/opr.db.connection";
	my $rtsmDBKey = "odb/odb.db.connection";
	
	#
	# Before 2018.11 - 10.71 - the key did not have opr/ or odb/odb
	#
	
	if (OpsB::Common::MyCompare($obmVersion, "10.71") == -1) {
		$eventDBKey = "opr.db.connection";
		$rtsmDBKey = "odb.db.connection";
	}
	
	#WO("Version: $obmVersion");
	my %event = OpsB::Checker::GetDBInfo($data, $eventDBKey, $online);
	$sev = M_INFO;
	
	if ((defined $event{"Host"}) && (length($event{"Host"}) > 0)){
		$msg = sprintf($MSG_MGMTDatabase, "Event", $event{"DBType"}, $event{"Host"}, $event{"Port"}, $event{"Database"}, $event{"User"});
		
		if ((defined $event{"SID"}) && (length($event{"SID"}) > 0)) {
			$msg = sprintf($MSG_MGMTDatabaseOra, "Event", $event{"DBType"}, $event{"Host"}, $event{"SID"}, $event{"Port"}, $event{"Database"}, $event{"User"});
		}

	}
	else {
		$msg = sprintf($MSG_NoDBInfo, "Event");
		$sev = M_WARN;
	}
	
	
	WO($msg, $sev);
	
	if ($sev == M_INFO) {
		#
		# If the host is different to the host for the management database...
		#
		
		if ((($mgmtdbOK == true) && (lc $DBInfo{"Host"} ne lc $event{"Host"})) || ($mgmtdbOK ==false)) {
			GetDBServerInfo(%event);
		}
		
		#
		# Invoke using the databse script to get some additional checks in the databse
		#

		if (-e $dbChecksFile  && $DO_DB == true) {
			my ($eServer, $eUser, $ePWD, $eDB, $ePort, $eSID, $eType) = ("", "", "", "", "", "", "");

			$eServer = $event{"Host"};
			$eDB = $event{"Database"};
			$eType = $event{"DBType"};

			if (defined $event{"User"}) {$eUser = $event{"User"}};
			if (defined $ARG_DBPWD) {$ePWD = $ARG_DBPWD};
			if (defined $event{"Port"}) {$ePort = $event{"Port"}};
			if (defined $event{"SID"}) {$eSID = $event{"SID"}};

			#
			# Override the port if required
			#

			if (length($ARG_Port) > 0) {
				$ePort = $ARG_Port;
			}

			#
			# Override the user if required
			#

			if (length($ARG_User) > 0) {
				$eUser = $ARG_User;
			}

			if ($ARG_Trusted == true) {
				$eUser = "";
				$ePort = "";
			}

			my $args = sprintf("-nowelcome -server \"%s\" -user \"%s\" -pwd \"%s\" -port \"%s\" -dbevent %s -dbtype %s -sid \"%s\"", $eServer, $eUser, $ePWD, $ePort, $eDB, $eType, $eSID);
			if ($ARG_Debug == true) {$args .= " -debug";}
			if ($ARG_Trusted == true) {$args .= " -trusted";}
			#
			# Run the database checks
			#

			WO($MSG_ETI_Checks, M_INFO);

			my $runOK = OpsB::Common::RunPerlScript($dbChecksFile, $args);		
		}

	}

	#
	# RTSM database
	#
	
	my %rtsm = OpsB::Checker::GetDBInfo($data, $rtsmDBKey, $online);
	$sev = M_INFO;
	
	if ((defined $rtsm{"Host"}) && (length($rtsm{"Host"}) > 0)){
		$msg = sprintf($MSG_MGMTDatabase, "UCMDB", $rtsm{"DBType"}, $rtsm{"Host"}, $rtsm{"Port"}, $rtsm{"Database"}, $rtsm{"User"});
		
		if ((defined $event{"SID"}) && (length($event{"SID"}) > 0)) {
			$msg = sprintf($MSG_MGMTDatabaseOra, "UCMDB", $rtsm{"DBType"}, $rtsm{"Host"}, $rtsm{"SID"}, $rtsm{"Port"}, $rtsm{"Database"}, $rtsm{"User"});
		}

	}
	else {
		$msg = sprintf($MSG_NoDBInfo, "UCMDB");
		$sev = M_NOTE;
	}
	
	WO($msg, $sev);	

	if ($sev == M_INFO) {
		#
		# If the host is different to the host for the management database...
		#
		
		if (($mgmtdbOK == true) && (lc $DBInfo{"Host"} ne lc $rtsm{"Host"}) || ($mgmtdbOK == false)) {
			
			if (lc $event{"Host"} ne lc $rtsm{"Host"}) {
				GetDBServerInfo(%rtsm);
			}
			
		}

		#
		# Invoke using the databse script to get some additional checks in the databse (RTSM)
		#

		if (-e $dbChecksFile && $DO_DB == true) {
			my ($rServer, $rUser, $rPWD, $rDB, $rPort, $rSID, $rType) = ("", "", "", "", "", "", "");

			$rServer = $rtsm{"Host"};
			$rDB = $rtsm{"Database"};
			$rType = $rtsm{"DBType"};

			if (defined $rtsm{"User"}) {$rUser = $rtsm{"User"}};
			if (defined $ARG_DBPWD) {$rPWD = $ARG_DBPWD};
			if (defined $rtsm{"Port"}) {$rPort = $rtsm{"Port"}};
			if (defined $rtsm{"SID"}) {$rSID = $rtsm{"SID"}};

			#
			# Override the port if required
			#

			if (length($ARG_Port) > 0) {
				$rPort = $ARG_Port;
			}

			#
			# Override the user if required
			#

			if (length($ARG_User) > 0) {
				$rUser = $ARG_User;
			}

			if ($ARG_Trusted == true) {
				$rUser = "";
				$rPWD = "";
			}

			my $args = sprintf("-nowelcome -server \"%s\" -user \"%s\" -pwd \"%s\" -port \"%s\" -dbrtsm %s -dbtype %s -sid \"%s\"", $rServer, $rUser, $rPWD, $rPort, $rDB, $rType, $rSID);
			if ($ARG_Debug == true) {$args .= " -debug";}
			if ($ARG_Trusted == true) {$args .= " -trusted";}

			#
			# Run the database checks
			#

			WO($MSG_UCMDB_Checks, M_INFO);

			my $runOK = OpsB::Common::RunPerlScript($dbChecksFile, $args);		
		}		
		
	}

	#
	# License checks
	#
	
	OpsB::Checker::GetLicenseInformation($data);
	
	#
	# Database checks
	#
	
	if (($DO_DB == true) && ($mgmtdbOK == true)) {
		GetDBInfo(%DBInfo);
	}
	
	#
	# LDAP TLS version checks
	#
	
	CheckLDAPTLS($data);
	
	#
	# Actually check the installed version against the expected version
	#
	
	if ($useVersion == true) {
		OpsB::Checker::CheckOBMVersion($version_data, $obmVersion, $obmBuild, $obmPatch);
	}
	else {
		$msg = sprintf($MSG_NoChecks, $versionsFile);
		WO($msg, M_WARN);
	}
	
	WO("ProcessData: End", M_DEBUG);
} # ProcessData

#
# See if LDAP server is the correct TLS version
#

sub CheckLDAPTLS() {
	my $data = shift;
	WO("CheckLDAPTLS: Start", M_DEBUG);
	
	if (!($data =~ /LDAP is enabled on your system/)) {
		return;
	}
	
	if (length($tlsUtil) == 0) {
		WO("The TLS Check utility was not found", M_DEBUG);
		return;
	}
	
	if ((length($ARG_Input) > 0) && ($ARG_ForceTLS == false)) {
		return;
	}
	
	if ($IsWindows) {
		#
		# See if perl.exe is om the path
		#
		
		my ($isOnPath) = OpsB::Common::FindFileOnPath("perl.exe");
		
		if ($isOnPath == false) {
			$perl = OpsB::Common::GetScriptDir($0) . "oaperl.bat";
		}
		
	}	
	
	my @array = split(chr(10), $data);
	my @ldap = grep(/ldap\.|java\./, @array);
	
	my ($domain, $server) = ("", "");
	
	for my $line(@ldap) {
		#
		# Only in here if at least one domain configired
		#
		
		if ((length($domain) > 0) && (length($server) > 0)) {
			ProcessLDAPServer($domain, $server);
			($domain, $server) = ("", "");
		}
		else {
			if ($line =~ /^ldap.unique.domain.name/) {$domain = $line;}
			if ($line =~ /^java.naming.provider.url/) {$server = $line;}
		}
		
	} # LDAP loop
	
	if ((length($domain) > 0) && (length($server) > 0)) {
		ProcessLDAPServer($domain, $server);
		($domain, $server) = ("", "");
	}
		
	WO("CheckLDAPTLS: End", M_DEBUG);
} #CheckLDAPTLS

#
# Do the TLS test for the LDAP server
#

sub ProcessLDAPServer() {
	my ($domain, $server) = @_;
	WO("ProcessLDAPServer: Start", M_DEBUG);
	
	#
	# Remove the start of the lines
	#
	
	my ($domainStart, $serverStart) = (length("ldap.unique.domain.name"), length("java.naming.provider.url"));
	$server = substr($server, $serverStart, length($server) - $serverStart);
	$domain = substr($domain, $domainStart, length($domain) - $domainStart);
	
	$server =~ s/ //g;
	$domain =~ s/ //g;
	
	#
	# server is a url - find host so we can figure out the port
	#
	
	my $host = OpsB::Common::GetHostFromUrl($server);
	
	#
	# The format is <protocol>://<host>[:<port>]/<additional>
	#
	# So split this on / and look for a match on the host. If we have that, stop processing ang just take that information as it 
	# will be the port. Then add protocaol https
	#
	
	my @array = split(/\//, $server);
	my $target = "";
	
	for my $item(@array) {
		
		if (substr($item, 0, length($host)) eq $host) {
			$target = sprintf("https://%s", $item);
			last;
		}
	}

	if (length($target) > 0) {
		WO("Processing LDAP server in domain $domain ...", M_INFO);
		
		#
		# Run the script that does the check
		#
		
		my $cmd = sprintf("\"%s\" \"%s\" -nowelcome -target %s", $perl, $tlsUtil, $target);
		if ($ARG_Log == true) {$cmd .= " -log";}
		if ($ARG_Color == false) {$cmd .= " -nocolor";}
		if ($ARG_Debug == true) {$cmd .= " -debug";}

		system($cmd);
	}
	
	WO("ProcessLDAPServer: End", M_DEBUG);
} #ProcessLDAPServer
#
# Get Database server information - version
#

sub GetDBServerInfo() {
	my %DBInfo = @_;
	
	#
	# Not if an input file was provided and force was not, or we previously failed
	#
	
	if ($DO_DB == false) {
		return;
	}
	
	my ($msg, $sev, $sid) = ("", M_INFO, "");
	
	if ((defined $DBInfo{"SID"}) && (length($DBInfo{"SID"}) > 0)) {
		$sid = $DBInfo{"SID"};
	}

	my $port = $DBInfo{"Port"};
	
	if (length($ARG_Port) > 0) {
		WO("Using override port: $ARG_Port", M_DEBUG);
		$port = $ARG_Port;
	}
	
	my $user = $DBInfo{"User"};
	
	if (length($ARG_User) > 0) {
		WO("Using override user: $ARG_User", M_DEBUG);
		$user = $ARG_User;
	}
	
	#
	# Trusted
	#

	my $pwd = $ARG_DBPWD;

	if ($ARG_Trusted == true) {
		$user = "";
		$pwd = "";
	}

	my $serverVersion = OpsB::Database::GetServerVersion($DBInfo{"Host"}, $port, $user, $pwd, $DBInfo{"Database"}, $DBInfo{"DBType"}, $sid);
	
	if (length($serverVersion) > 0) {
		$msg = sprintf($MSG_ServerVersion, $serverVersion);
		
		#
		# Now check to see if the version is supported for the latest OBM
		#
		
		if ($useVersion == true) {
			my @all = split(chr(10), $version_data);
			my @dbData = grep(/\<OBMDBVersion/, @all);
			
			if (scalar @dbData > 0) {
				#
				# Only if the data is available
				##
				
				my ($supported, $supportedName, $found) = ("", "", false);
				
				for my $line(@dbData) {
					my $product = OpsB::Common::GetAttributeFromData($line, "Product");
					
					if ($product eq $DBInfo{"DBType"}) {
						$found = true;
						$supported = OpsB::Common::GetAttributeFromData($line, "VersionSupported");
						$supportedName = OpsB::Common::GetAttributeFromData($line, "VersionName");
						if (length($supportedName) == 0) {$supportedName = $supported;}
						
						last;
					}
				}
				
				if ($found == true) {
					#
					# See if the version is OK#
					#
				
					if (OpsB::Common::MyCompare($serverVersion, $supported) == -1) {
						#
						# Not Supported
						#
						$msg = sprintf($MSG_DBServerLow, $DBInfo{"DBType"}, $serverVersion, $ThisVersionExternal, $supportedName);
						$sev = M_WARN;					
					}
					else {
						#
						# Supported
						#
					
						$msg = sprintf($MSG_DBServerOK, $DBInfo{"DBType"}, $serverVersion, $ThisVersionExternal);
						$sev = M_OK;
					}
							
				}
			
			}
			
		}
		
		WO($msg, $sev);
		
		#
		# SPECIAL CASE - Oracle 12c support ends from Oracle Novembner 2020
		#
		
		if ((defined $DBInfo{"DBType"}) && ($DBInfo{"DBType"} =~ /Oracle/i)) {
			
			if (OpsB::Common::MyCompare($serverVersion, "19.0") == -1) {
				WO("Oracle support for 12c ends in November 2020, consider upgrading Oracle in order to continue support", M_WARN);
			}
			
		}
		
	}
	else {
		#
		# If there is no server version then something failed - disable future database checks
		#
		
		WO("Unable to fetch database server information. Make sure the credentials supplied for the connection are correct. Database checks will be disabled", M_ERROR);
		$DO_DB = false;
	}
	
} #GetDBServerInfo

#
# Get Database information
#

sub GetDBInfo() {
	my %DBInfo = @_;
	
	#
	# Not if an input file was provided and force was not, or we previously failed
	#
	
	if ($DO_DB == false) {
		return;
	}
	
	my ($msg, $sev, $sid) = ("", M_INFO, "");
	
	if ((defined $DBInfo{"SID"}) && (length($DBInfo{"SID"}) > 0)) {
		$sid = $DBInfo{"SID"};
	}

	my $port = $DBInfo{"Port"};
	
	if (length($ARG_Port) > 0) {
		WO("Using override port: $ARG_Port", M_DEBUG);
		$port = $ARG_Port;
	}

	my $user = $DBInfo{"User"};
	
	if (length($ARG_User) > 0) {
		WO("Using override user: $ARG_User", M_DEBUG);
		$user = $ARG_User;
	}

	my $pwd = $ARG_DBPWD;

	if ($ARG_Trusted == true) {
		$user = "";
		$pwd = "";
	}

	my $servers = OpsB::Database::GetServerCountByType(OpsB::Database::STYPE_GW, $DBInfo{"Host"}, $port, $user, $pwd, $DBInfo{"Database"}, $DBInfo{"DBType"}, $sid);
	
	if (length($servers) > 0) {
		WO($servers, M_INFO);
	}

	$servers = OpsB::Database::GetServerCountByType(OpsB::Database::STYPE_DPS, $DBInfo{"Host"}, $port, $user, $pwd, $DBInfo{"Database"}, $DBInfo{"DBType"}, $sid);
	
	if (length($servers) > 0) {
		WO($servers, M_INFO);
	}

	$servers = OpsB::Database::GetServerCountByType(OpsB::Database::STYPE_CENTER, $DBInfo{"Host"}, $port, $user, $pwd, $DBInfo{"Database"}, $DBInfo{"DBType"}, $sid);
	
	if (length($servers) > 0) {
		WO($servers, M_INFO);
	}
	
} #GetDBServerInfo

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
	$ARG_Timeout = OpsB::Common::GetTimeout(OpsB::Common::FindArg("timeout"));
	
	#
	# Switch around the color settings - found value for "nocolor" so if that is true, set "ARG_Color" to false;
	#
	
	if ($ARG_Color == true) {$ARG_Color = false;} else {$ARG_Color = true;}
	
	#
	# Script specific args and switches to be handled below
	#
	
	$ARG_Input = OpsB::Common::FindArg("input");
	$ARG_DBPWD = OpsB::Common::FindArg("pwd");
	$ARG_DODB = OpsB::Common::FindSwitch("forcedb");	# Where the output is in a file and we can contact the database server
	$ARG_Port = OpsB::Common::FindArg("port");	# Override the port from the config
	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_ForceTLS = OpsB::Common::FindSwitch("forcetls");	# Force TLS even from offline mode (reading file)
	$ARG_Trusted = OpsB::Common::FindSwitch("trusted");
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
	
	if ($useVersion == false) {
		$error = OpsB::Common::AddString($error, sprintf("The version information file cannot be located: ", $versionsFile), "\n");
		$ok = false;
	}
	
	if ((length($ARG_Input) > 0) && ($ARG_DODB == false)) {
		#
		# When using an iunput file, assume we have no access to the Database Server
		#
		
		$DO_DB = false;
	}
	
	#
	# If we were asked to override the input file - or if there is no input file then assume we should check the database server
	#
	
	if ((length($ARG_Input) == 0) || ($ARG_DODB == true)) {
		#
		# Make sure we have a password
		#
		
		if ($ARG_Trusted == true) {

			if ($IsWindows == false) {
				$error = OpsB::Common::AddString($error, "Trusted connection is only supported for Windows and SQL Server", chr(10));
				$ok = false;
			}
			else {
				$DO_DB = true;
			}

		}
		else {

			if (length($ARG_DBPWD) == 0) {
				$error = OpsB::Common::AddString($error, "No password was supplied for the database checks", chr(10));
				$ok = false;
			}
			else {
				$DO_DB = true;
			}

		}
				
	}
	
	if (length($ARG_Port) > 0) {
		#
		# Undocumented but only use if numeric
		#
		
		my $numeric = OpsB::Common::MakeStringNumeric($ARG_Port);
		
		if ($ARG_Port ne $numeric) {
			WO("Port override: $ARG_Port will not be used", M_DEBUG);
			$ARG_Port = "";
		}
	}
	
	return $ok, $error;
	
	WO("CheckInputs: End", M_DEBUG);
} # CheckInputs

#
# Show our help
#

sub ShowHelp() {
	#
	# Add Script Specific help
	#
	
	WO("");
	WO(OpsB::Common::MSG_Help_Start);
	WO("");
	
	WO("  -input <file>\t\tThe input file for offline processing");
	WO("  -pwd <password>\tPassword for the database checks (the configured user account will be used)");
	WO("");
	
	WO("Advanced options");
	WO("");
	WO("  -user <user>\t\tDatabase username to use instead of the configured user");
	WO("  -forcedb\t\tForce database checks if an input file is used");
	
	OpsB::Common::CommonHelp();
}

#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();