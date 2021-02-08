#!/usr/bin/perl

# ++
# File:     opr-versioc-check.pl
# Created:  Jun-2020, by Andy
# Reason:   Wrapper for the OBM related utilities for the upgrade check tool
# --
# Abstract: This is a perl script that drives additional perl scripts.
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	29-Jun-2020	Created (update to V2 from earlier release)
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
use OpsB::Common qw(WO true false $IsWindows M_NONE M_INFO M_OK M_WARN M_ERROR M_FATAL M_DEBUG $ARG_Debug $ARG_Log $ARG_Color $ARG_Quiet $ARG_Timeout $ARG_NoWelcome $ARG_Help); 

use OpsB::HPBSM;
use OpsB::HPBSM qw(TopazDir HP_BSM_MODULE_VERSION $Java);

#
# required
#

our $scriptVersion = "2020.12.14";
our $scriptArgs = "user,pwd,dbuser,dbpwd,shared-user,shared-pwd,online,offline,obm-input,mp-input,dbport,forcedb,forcetls,trusted";

#
# Messages
#

our $MSG_OnlineOffline = "Running script in \"%s\" mode";

#
# Script Specific Arguments
#

our $ARG_Online = false;
our $ARG_Offline = false;

our $ARG_OBMUser = "";
our $ARG_OBMPWD = "";
our $ARG_OBMInput = "";

our $ARG_MPInput = "";

our $ARG_OBMDBUser = "";
our $ARG_OBMDBPWD = "";
our $ARG_DBPORT = "";
our $ARG_ForceDB = false;
our $ARG_ForceTLS = false;
our $ARG_Trusted = false;

#
# Available utilities
#

our $online = 1;
our $offline = 2;
our $both = 3;

our @Utilities = ("run-opr-checker.pl:OBM Infrastructure:$both", "run-content-manager.pl:Management Packs:$both", "connectors.pl:OBM Connectors:$online", "run-opr-connected-server.pl:Connected Servers:$online","run-opr-user.pl:OBM Users:$online");
our $description = "This tool will provide you with valuable information for your upgrade planning to classic OBM 2020.10. OBM 2020.10 provides a Flash-independent user interface for Operational tasks and administration tasks. Running a Flash-independent version of OBM by end of calendar year 2020 is very important if your company is following the Adobe Flash-Player removal initiative. Otherwise, please make sure that you can still run Adobe Flash-Player in your browsers beyond the end of 2020.";

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
	
	my $additionalModules = sprintf("HPBSM Version: %s", OpsB::HPBSM::HP_BSM_MODULE_VERSION);
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
	
	my ($processedSomething, $dir) = (false, OpsB::Common::GetScriptDir($0));
	my ($msg, $type) = ("", "offline");
	
	if ($ARG_Online == true) {$type = "online";}
	
	$msg = sprintf($MSG_OnlineOffline, $type);
	WO($msg, M_INFO);

	for my $utilityData(@Utilities) {
		my @array = split(/:/, $utilityData);
		my($script, $description, $type) = ($array[0], $array[1], $array[2]);
		
		#WO("Script: $script, $description, $type");
		
		my ($utilOnline, $utilOffline, $runThis)  = (false, false, false);
		if (($type & $online) == $online) {$utilOnline = true;}
		if (($type & $offline) == $offline) {$utilOffline = true;}
	
		if (($ARG_Online == true && $utilOnline == true) || (($ARG_Offline == true && $utilOffline == true))) {
			$runThis = true;
		}
				
		if ($runThis == true) {
			$script = $dir . $script;
			RunScript($script, $description);
			$processedSomething = true;
		}
		
	}

	if ($processedSomething == true) {
		WO("");
		WO("In case you need more information about the Micro Focus Operations Bridge Evolution program, please contact your Micro Focus");
		WO("Support liaison, or send an email to OpsBEvolution\@MicroFocus.com");
		WO("");
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
	
	if ($script =~ /run-opr-checker/i) {
		
		if (length($ARG_OBMDBUser) > 0) {
			$args .= " -user \"$ARG_OBMDBUser\"";
		}
		
		if (length($ARG_OBMDBPWD) > 0) {
			$args .= " -pwd \"$ARG_OBMDBPWD\"";
		}
		
		if (length($ARG_OBMInput) > 0) {
			$args .= " -input \"$ARG_OBMInput\"";
		}
		
		if (length($ARG_DBPORT) > 0) {
			$args .= " -port $ARG_DBPORT";
		}
		
		if ($ARG_Trusted == true) {
			$args .= " -trusted";
		}

		#
		# More for testing ...
		#
		
		if ($ARG_ForceDB == true) {
			$args .= " -forcedb";
		}
		
		if ($ARG_ForceTLS == true) {
			$args .= " -forcetls";
		}

	}

	if (($script =~ /connectors/i) || ($script =~ /connected-server/i) || ($script =~ /opr-user/i) || ($script =~ /content-manager/i)) {
		
		if (length($ARG_OBMUser) > 0) {
			$args .= " -user \"$ARG_OBMUser\"";
		}
		
		if (length($ARG_OBMPWD) > 0) {
			$args .= " -pwd \"$ARG_OBMPWD\"";
		}
		
	}
	
	if ($script =~ /content-manager/i) {
		
		if ($ARG_Offline == true) {
			$args .= " -input \"$ARG_MPInput\"";

			if (length($ARG_MPInput) == 0) {
				WO("Cannot check Management Packs in offline mode without an input file", M_DEBUG);
				return;
			}
			
		}
		
		$args .= " -mp";
	}
		
	WO("");
	WO("**** Running script for $description ...", M_INFO);
	WO("");
	
	my $runOK = OpsB::Common::RunPerlScript($script, $args);

	WO("");
	WO("**** Finished running script for $description ... ", M_INFO);

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
	$ARG_Timeout = OpsB::Common::GetTimeout(OpsB::Common::FindArg("timeout"));

	#
	# Switch around the color settings - found value for "nocolor" so if that is true, set "ARG_Color" to false;
	#
	
	if ($ARG_Color == true) {$ARG_Color = false;} else {$ARG_Color = true;}
	
	#
	# Script specific args and switches to be handled below
	#
	
	$ARG_OBMUser = OpsB::Common::FindArg("user");
	$ARG_OBMPWD = OpsB::Common::FindArg("pwd");
	$ARG_OBMInput = OpsB::Common::FindArg("obm-input");
	
	$ARG_MPInput = OpsB::Common::FindArg("mp-input");
	
	$ARG_OBMDBUser = OpsB::Common::FindArg("dbuser");
	$ARG_OBMDBPWD = OpsB::Common::FindArg("dbpwd");
	$ARG_DBPORT = OpsB::Common::FindArg("dbport");	
	$ARG_ForceDB = OpsB::Common::FindSwitch("forcedb");
	$ARG_ForceTLS = OpsB::Common::FindSwitch("forcetls");
	$ARG_Trusted = OpsB::Common::FindSwitch("trusted");

	$ARG_Online = OpsB::Common::FindSwitch("online");
	$ARG_Offline = OpsB::Common::FindSwitch("offline");
	
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
	# If there is no specific database password, use the OBM password
	#
	
	if (length($ARG_OBMDBPWD) == 0) {
		$ARG_OBMDBPWD = $ARG_OBMPWD;
	}
	
	if (length($ARG_OBMInput) > 0) {
		#
		# See if the file exists
		#
		
		if (-e $ARG_OBMInput) {
			$ARG_Online = false;
			$ARG_Offline = true;
		}
		else {
			
			if ($ARG_Offline == true) {
				$error = "The OBM input file is invalid";
				$ok = false;
			}
			
		}
	}
	
	#
	# If offline is specified - need the file
	#
	
	if ($ARG_Offline == true) {
		
		if (length($ARG_OBMInput) == 0) {
			$error = OpsB::Common::AddString($error, "For offline mode, the OBM Input file is required", chr(10));
			$ok = false;
		}
		else {
			$ARG_Online = false;
		}
		
	}
	
	if ($ARG_Online == false && $ARG_Offline == false) {
		$ARG_Online = true;
	}
	
	if ($ARG_Online == true) {
		#
		# Need the Topaz directory to exists
		#
		
		my ($dirOK, $dir) = OpsB::HPBSM::TopazDir();
		
		if ($dirOK == false) {
			$error = OpsB::Common::AddString($error, "For online mode, this script needs to run on a DPS or Gateway server", chr(10));
			$ok = false;
		}

		if ($ARG_Trusted == true) {

			if ($IsWindows == false) {
				$error = OpsB::Common::AddString($error, "Trusted authentication can only be used on Windows with SQL Server", chr(10));
				$ok = false;
			}
		}
		else {

			if (length($ARG_OBMPWD) == 0) {
				$error = OpsB::Common::AddString($error, "For online mode, the OBM user and OBM Database passwords are required", chr(10));
				$ok = false;
			}

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
	# In this case we will provide examples of running this script. So determine the required information here
	#
	
	my $scriptPath = OpsB::Common::GetScriptDir($0);
	my ($gotTopaz, $topazDir) = OpsB::HPBSM::TopazDir();
	
	my ($thisScript, $checkerUtil, $supportUtil, $normal, $exInput) = ($scriptPath . "opr-version-check.pl", "", "", "/opt/HP/BSM/", "/tmp/opr-checker.txt");
	
	if ($gotTopaz == false) {
		$topazDir = "<path>";
	}

	$checkerUtil = $topazDir . "opr/support/opr-checker.pl";
	$supportUtil = $topazDir . "opr/support/opr-support-utils.sh";
	
	if ($IsWindows) {
		$thisScript =~ s/\//\\/g;
		$checkerUtil =~ s/\//\\/g;
		$checkerUtil .= ".bat";
		$supportUtil =~ s/\//\\/g;
		$supportUtil .= ".bat";		
		$normal = "C:\\HPBSM\\";
		$exInput = "C:\\TEMP\\opr-checker.txt";
	}
	
	
	WO("");
	WO(OpsB::Common::MSG_Help_Start);
	WO("");
		
	#
	# Add Script Specific help
	#
	
	WO("Running \"online\" (using the -online switch)");
	WO("-------------------------------------------");
	WO("");
	WO("  -user <user>\t\tUsername for OBM connections (optional)");
	WO("  -pwd <password>\tThe password for the OBM user (required)");
	WO("  -dbuser <user>\tThe username for database connections (optional)");
	WO("  -dbpwd <password>\tThe password for the database user (optional - if not specified, the OBM user password will be used)");
	WO("");
	WO("  To run in \"online\" mode, the script must be executed on either a Gateway or DPS server. The user for connections to OBM will be \"admin\" if it is not");
	WO("  specified using the \"-user\" parameter. If the database password (\"-dbpwd\") is not provided, then the password for the OBM user will be used.");
	WO("");
	WO("  The script will determine the user for database access from the OBM configuration. This can be overridden using the \"-dbuser\" parameter");
	WO("");
	WO("  Examples of using \"online\" mode:");
	WO("");
	WO("    $thisScript -online -pwd P\@ssw0rd");
	WO("    $thisScript -online -pwd P\@ssw0rd -dbpwd P\@ssw0rd2");
	WO("");
	
	WO("");
	WO("Running \"offline\" (using the -online switch)");
	WO("--------------------------------------------");
	WO("");
	WO("  -obm-input <file>\tThe input file to use for OMi/OBM (required)");
	WO("  -mp-input <file>\tThe input file to use for Management Pack information");
	WO("");
	WO("  Example of using \"online\" mode:");
	WO("");
	WO("    $thisScript -offline -obm-input $exInput");
	WO("");
	WO("  To run in \"offline\" mode, the OBM utilities need to have been used to extract the information to be processed. Depending on the OpsBridge version (and platform),");
	WO("  multiple utilties may be required. See the documentation for specifics according to the version installed. The utilities to use are:");
	WO("");
	WO("    $checkerUtil -sys -opr -rapid");
	WO("    $supportUtil -list_settings -context opr");
	WO("    $supportUtil -list_settings -context odb");
	WO("");
	
	if ($gotTopaz == false) {
		WO("  Replace \"\<path\>\" with the path to the installation directory which is normally \"$normal\"");
		WO("");
	}
	
	WO("  The output for these utilities should be captured in a file to use as the input to the script (if multiple utilities are required, concatonate the output into a");
	WO("  single file otherwise some information will be missing when the file is processed).");
	WO("");
	
	OpsB::Common::CommonHelp();
		
}

#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();