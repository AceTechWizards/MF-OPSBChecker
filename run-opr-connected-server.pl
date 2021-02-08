#!/usr/bin/perl

# ++
# File:     run-obr-checks.pl
# Created:  May-2020, by Andy
# Reason:   Run OBR checks
# --
# Abstract: Standalone OBR check utility
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	May-2020	Created
#			Andy	29-Jun-2020	Version 2 update
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
use OpsB::HPBSM qw(TopazDir);

our $HPBSM_Module_Version = OpsB::HPBSM::HP_BSM_MODULE_VERSION;

#
# required
#

our $scriptVersion = "2020.12";
our $scriptArgs = "user,pwd";

#
# Messages
#

our $MSG_ProcessingServer = "Connected server: %s, connection type: %s";
our $MSG_Totals = "Total of %s Active and %s Inactive Connected Servers (only active connected server details shown)";

#
# Script Specific Arguments
#

our $ARG_User;
our $ARG_PWD;

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
	
	my $argValues = sprintf("\n\t-user = %s\n", $ARG_User);	
	OpsB::Common::ShowInputs($argValues);
	
	#
	# Show banner
	#
	
	my $additionalModules = sprintf("HPBSM Version: %s", $HPBSM_Module_Version);
	OpsB::Common::SayHello($scriptVersion, $additionalModules, "Script to list the connected servers in the OBM/Omi environment"); # ScriptVersion, AdditionalModules, Specific Description 
	
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
	
	#
	# Get the HPBSM directory and quit if not found
	#
			
	my ($installed, $topaz) = TopazDir();
	
	if ($installed == false) {
		WO(OpsB::Common::MSG_TopazMissing, M_FATAL);
		return;
	}
		
	#
	# Check the utility exists and quit if not
	#
	
	if (OpsB::HPBSM::ConnectedServersExists() == false) {
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
	# Get the list of connected servers#
	#
	
	my ($ok, $list) = OpsB::HPBSM::GetConnectedServers($ARG_User, $ARG_PWD);
	
	if ($ok = false) {
		#
		# Errors handled in the caller
		#
		
		return;
	}
	
	#
	# We have data so process it
	#
	
	my @array = split(chr(10), $list);
	my ($totalActive, $totalInactive) = (0, 0);

	for my $line(@array) {
		#
		# Each server is comprissed a tab delimted line with the name, type and GUID (ID)
		#
		
		my @serverArray = split(chr(9), $line);
		my ($name, $type, $id) = ($serverArray[0], $serverArray[1], $serverArray[2]); 

		my $msg = sprintf($MSG_ProcessingServer, $name, $type);

		#
		# Write the info only if this is active
		#
		
		my ($serverOK, $isActive) = OpsB::HPBSM::ProcessConnectedServer($id, $msg, $ARG_User, $ARG_PWD);
		
		if ($serverOK == true) {
			
			if ($isActive == true) {
				$totalActive +=1;
			}
			else {
				$totalInactive +=1;
			}
		}
			
	}
	
	my $finalMsg = sprintf($MSG_Totals, $totalActive, $totalInactive);
	WO($finalMsg, M_INFO);
	
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

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
	
	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_PWD = OpsB::Common::FindArg("pwd");
	
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
	
	if (length($ARG_User) == 0) {
		$ARG_User = "admin";
	}
	
	if (length($ARG_PWD) == 0) {
		$error = "The password cannot be blank";
		$ok = false;
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
	
	WO("  -user <user>\t\tThe username to connect to the Gateway server (if not specified, \"admin\" is used)");
	WO("  -pwd <password>\tThe password for the specified user");
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