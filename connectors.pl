#!/usr/bin/perl

# ++
# File:     connectors.pl
# Created:  Jun-2020, by Andy
# Reason:   OpsBridge upgrade check - look for the installed connectors and information on related servers
# --
# Abstract: This script looks for the connectors installed and the related content packs
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	29-Jun-2020	Update of original for V2 release
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

use OpsB::OVDeploy;
use OpsB::OVDeploy qw(OV_VERSION $OVDeploy $OprAgt $Dummy_Win $Dummy_Unix);

our $HPBSM_Module_Version = OpsB::HPBSM::HP_BSM_MODULE_VERSION;
our $OVDEPLOY_Version = OpsB::OVDeploy::OV_VERSION;

#
# required
#

our $scriptVersion = "2.0";
our $scriptArgs = "user,pwd,dummy";

#
# Messages
#

#
# Script Specific Arguments
#

our $ARG_User = "admin";
our $ARG_PWD = "";
our $ARG_Dummy = false;

#
# For version information
#

our ($useVersion, $version_data, $versionError) = (false, "", "");
our $versionsFile = OpsB::Common::GetScriptDir($0) . OpsB::Common::VERSIONS_FILE;
if (-e $versionsFile) {($useVersion, $version_data, $versionError) = OpsB::Common::ReadFileToString($versionsFile);}

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
	
	my $additionalModules = sprintf("OVDeploy Version: %s, HPBSM Version: %s", $OVDEPLOY_Version, $HPBSM_Module_Version);
	OpsB::Common::SayHello($scriptVersion, $additionalModules, "Display connector information"); # ScriptVersion, AdditionalModules, Specific Description 
	
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
	# This requires ovdeploy and cannot carry on without it
	#
	
	my $ok = false;
	
	($ok, $OVDeploy) = OpsB::OVDeploy::GetOVDeploy();
	
	if ($ok == false) {
		return;
	}
	
	#
	# Also needs the opr-agt utility
	#
	
	($ok, $OprAgt) = OpsB::OVDeploy::GetOprAgt();
	
	if ($ok == false) {
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
	
	GetStandardConnectors();
	GetConnectorsFromContentManager();

	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Use content manager to list the remaining connector information
#

sub GetConnectorsFromContentManager() {
	WO("GetConnectorsFromContentManager: End", M_DEBUG);

	if ($ARG_Dummy == true) {
		return;
	}
	
	#
	# The script run-content-manager has this functionality, so use it
	#
	
	my $util = OpsB::Common::GetScriptDir($0) . "run-content-manager.pl";
	
	if (!(-e $util)) {
		WO("The content manager script is missing", M_DEBUG);
		return;
	}
		
	my $args = sprintf("-nowelcome -user \"%s\" -pwd \"%s\" -cnx", $ARG_User, $ARG_PWD);
	
	#WO("");
	WO("Checking for OBM Connectors installed as content packs...", M_INFO);
	my $runOK = OpsB::Common::RunPerlScript($util, $args);
	
	WO("GetConnectorsFromContentManager: End", M_DEBUG);
} # GetConnectorsFromContentManager

#
# Use the opr-agt utility to find the standard connectors
#

sub GetStandardConnectors() {
	WO("GetStandardConnectors: Start", M_DEBUG);
	
	#
	# Run the utility to get the results
	#
	
	my ($data, $msg, $ok) = ("", "", false);
	
	if ($ARG_Dummy == true) {
		#
		# Use dummy input, undocumented
		#
		
		my $dummyFile = OpsB::Common::GetScriptDir($0) . "opr-agt_view_oc.txt";
		
		if (-e $dummyFile) {
			($ok, $data) = OpsB::Common::ReadFileToString($dummyFile)
		}
		else {
			WO("The dummy input file $dummyFile is missing", M_ERROR);
			return;
		}
		
		$dummyFile = OpsB::Common::GetScriptDir($0) . "wmic_out.txt";
		
		if (-e $dummyFile) {
			($ok, $Dummy_Win) = OpsB::Common::ReadFileToString($dummyFile)
		}
		else {
			WO("The dummy input file $dummyFile is missing", M_ERROR);
			return;
		}		

		$dummyFile = OpsB::Common::GetScriptDir($0) . "qa_out.txt";
		
		if (-e $dummyFile) {
			($ok, $Dummy_Unix) = OpsB::Common::ReadFileToString($dummyFile)
		}
		else {
			WO("The dummy input file $dummyFile is missing", M_ERROR);
			return;
		}		

	}
	else {
		#
		# Use the live command
		#
		
		WO("Fetching connector servers...", M_INFO);
		
		my $cmd = sprintf("\"%s\" -user \"%s\" -password \"%s\" -agent_version -view_name \"Operations Connectors\"", $OprAgt, $ARG_User, $ARG_PWD);

		my ($ok, $rc, $stdout, $stderr) = OpsB::Common::RunCommand($cmd);
		
		if (($ok == false) || ($rc != 0) || (length($stderr) > 0)) {
			$msg = sprintf("Failed to run command to fetch connector information, return code: %s", $rc);
			if (length($stderr) > 0) {$msg .= ".Error: $stderr";}
			
			WO($msg, M_ERROR);
			return;
		}
	
		$data = $stdout
	}

	#
	# Make sure that there were some servers listed
	#
	
	if ($data =~ /The query showed no systems/i) {
		our $MSG_NoConnectors = "There are no connectors installed";
		WO($MSG_NoConnectors, M_INFO);
		return;
	}
	
	#
	# Process the results which are in the form 
	#
	# <SERVER>:<PORT>: OK
	# NAME	DESCRIPTION	VERSION	TYPE	OSTYPE
	# <Package Name>	<Package Desc>	<Package Version>	<Package Type>	<OS Type> [multiple rows]
	# Operations-agent	Operations Agent Product	<version>	<OS>
	#
	
	my @array = split(chr(10), $data);
	my ($processingServer, $lastLine, $server) = (false, "", "");
		
	for my $line(@array) {
		
		if ($processingServer == false) {
			#
			# Check to see if we have the header - the previous line will then contain the server
			#
			
			if ($line =~ /^NAME/) {
				#
				# Last line has server in the form of <server>:<port>: OK - get the server as item 1
				$processingServer = true;
				my @serverArray = split(":", $lastLine);
				$server = $serverArray[0];				
			} # Found a header
			
		} # Not processing server
		else {
			#
			# Look to see if we are at the end of processing this server
			#
						
			if (($line =~ /^Operations-agent/) && ($line =~/ Operations Agent Product/)) {
				#
				# Get the version and OS information from this line
				#
				
				$processingServer = false;
				my @infoArray = split(" ", $line);
				
				#
				# Version and OS are the end of the array, so doesn;t matter that the line is split on words
				#
				my $arraySize = scalar @infoArray;
				my $version = $infoArray[$arraySize -3];
				my $os = $infoArray[$arraySize -1];
				
				OpsB::OVDeploy::ProcessRemoteServer($server, $os, $version, $version_data);
				WO("");
			} # last ;line
			
		} # Processing server
		
		$lastLine = $line;
	} # loop
	
	WO("GetStandardConnectors: End", M_DEBUG);
} #GetStandardConnectors

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

	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_PWD = OpsB::Common::FindArg("pwd");
	$ARG_Dummy = OpsB::Common::FindSwitch("dummy");
	
} # GetInputs

#
# Make sure the inputs are ok and change adjust as needed
#
sub CheckInputs() {
	WO("CheckInputs: Start", M_DEBUG);
	
	#
	# Change value to false if any information is bad. Se the Error string to hold all error messages so they can be displayed later
	#
	
	my ($ok, $error) = (true, "");
	
	if (length($ARG_User) == 0) {
		$ARG_User = "admin";
	}
	
	if (length($ARG_PWD) == 0) {
		$error = "The password cannot be blank";
		$ok = false;
	}
	
	WO("CheckInputs: End", M_DEBUG);

	return $ok, $error;	
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
	
	WO("  -user <user>\t\tThe user required to connect to the OBM/OMi server. If not specified, \"admin\" will be used");
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