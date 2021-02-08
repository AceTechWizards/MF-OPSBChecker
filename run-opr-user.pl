#!/usr/bin/perl

# ++
# File:     run-opr-user.pl
# Created:  Jun-2020, by Andy
# Reason:   run the built in opr-user tool
# --
# Abstract: Part of upgrade check utility
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
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
our $scriptArgs = "user,pwd,nousers,groups,roles";

#
# Messages
#

#
# Script Specific Arguments
#

our $ARG_User = "";
our $ARG_PWD = "";
our $ARG_Users = true;
our $ARG_Groups = false;
our $ARG_Roles = false;

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
	
	my $argValues = sprintf("\n\t-user = %s\n\t-users = %s\n\t-groups = %s\n\t-roles = %s\n", $ARG_User, $ARG_Users, $ARG_Groups, $ARG_Roles);
	OpsB::Common::ShowInputs($argValues);
	
	#
	# Show banner
	#
	
	my $additionalModules = sprintf("HPBSM Version: %s", $HPBSM_Module_Version);
	OpsB::Common::SayHello($scriptVersion, $additionalModules, "Utility to fetch user/group/role information for OBM/OMi server"); # ScriptVersion, AdditionalModules, Specific Description 
	
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
	
	if (OpsB::HPBSM::UsersUtilExists() == false) {
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
	
	if ($ARG_Users == true) {
		OpsB::HPBSM::RunUsersUtil($ARG_User, $ARG_PWD, OpsB::HPBSM::TYPE_Users);
	}
	
	if ($ARG_Groups == true) {
		OpsB::HPBSM::RunUsersUtil($ARG_User, $ARG_PWD, OpsB::HPBSM::TYPE_Groups);
	}

	if ($ARG_Roles == true) {
		OpsB::HPBSM::RunUsersUtil($ARG_User, $ARG_PWD, OpsB::HPBSM::TYPE_Roles);
	}

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
	
	#
	# Users is default - so the nousers switch is used to disable that
	#
	
	my $nousers = OpsB::Common::FindSwitch("nousers");
	if ($nousers == true) {$ARG_Users = false;}
	
	$ARG_Groups = OpsB::Common::FindSwitch("groups");
	$ARG_Roles = OpsB::Common::FindSwitch("roles");
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
	
	if (($ARG_Users == false) && ($ARG_Groups == false) && ($ARG_Roles == false)) {
		$error = OpsB::Common::AddString($error, "At least one option for users/groups/roles must be specified", chr(10));
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
	
	WO("  -user <user>\t\tThe user to connect to the Gateway server (if not specified, \"admin\" is used)");
	WO("  -pwd <password>\tThe password for the specified user");
	
	OpsB::Common::CommonHelp();
}

#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();