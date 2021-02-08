#!/usr/bin/perl

# ++
# File:     tls-check.pl
# Created:  Jun-2020
# Reason:   Make a TLS check to see if the server is on V1.0 or not
# --
# Abstract: Uses the OpsB java utilities that need to be shipped along with this
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	30-Jun-2020	Created
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

our $scriptVersion = "2020.12";
our $scriptArgs = "target,client";

#
# Messages
#

#
# Script Specific Arguments
#

our $ARG_Target = "";
our $ARG_Client = false;

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
	
	my $additionalModules = sprintf("HPBSM Version: %s", OpsB::HPBSM::HP_BSM_MODULE_VERSION);
	OpsB::Common::SayHello($scriptVersion, $additionalModules, "Perfome TLS Version checks against the target system"); # ScriptVersion, AdditionalModules, Specific Description 
	
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
	
	my $msg = "";
	
	if (length($Java) == 0) {
		WO("This utility requires Java to be present on the system", M_FATAL);
		return;
	}
	
	#
	# Get the path to the utility
	#
	
	my $tls_util = OpsB::Common::GetScriptDir($0) . "lib/java/opr-tlstest-jar-with-dependencies.jar";
	
	if (!( -e $tls_util)) {
		WO("The TLS Test utility is missing. Checked $tls_util", M_FATAL);
		return;
	}
	
	my $cmd = sprintf("\"%s\" -jar \"%s\" -trustall -target %s", $Java, $tls_util, $ARG_Target);
	
	if ($IsWindows == true) {
		$cmd .= " | findstr Hello";
	}
	else {
		$cmd .= " | grep Hello";
	}

	WO("Checking TLS on target: $ARG_Target ...", M_INFO);
	
	my ($ok, $rc, $stdout, $stderr) = OpsB::Common::RunCommand($cmd);

	if (($ok == false) || ($rc != 0) || (length($stderr) > 0)) {
		$msg = "The TLS test failed with return code: $rc";
		
		if (length($stderr) > 0) {
			$msg .= ". Error: $stderr";
		}
		
		$msg .= "\n\tVerify the server $ARG_Target can be reached";
		
		WO($msg, M_ERROR);
	}
	else {
		ProcessOutput($stdout);
	}
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

sub ProcessOutput() {
	my $data = shift;
	WO("ProcessOutput: Start", M_DEBUG);
	
	my ($msg, $ThisVersion, $ThisVersionExternal, $TLSVersionMin, $TLSVersionRecommended) = ("", "", "", "", "");
	my $showRecommended = false;
	
	#
	# Get the version we are aiming for
	#
	
	if ($useVersion == true) {
		my $info = OpsB::Common::FindLineWithKey($version_data, "<Main Version=");
		
		if (length($info) > 0) {
			$ThisVersion = OpsB::Common::GetAttributeFromData($info, "InternalVersion");
			$ThisVersionExternal = OpsB::Common::GetAttributeFromData($info, "Version");
		}
		
		$info = OpsB::Common::FindLineWithKey($version_data, "<TLS");

		if (length($info) > 0) {
			$TLSVersionMin = OpsB::Common::GetAttributeFromData($info, "MinimumVersion");
			$TLSVersionRecommended = OpsB::Common::GetAttributeFromData($info, "RecommendedVersion");
		}
		
	}
	
	my @array = split(chr(10), $data);
	my ($showMessage, $gotServer) = (false, false);
	
	for my $line(@array) {
		if ($line =~ /TLS/i) {
			WO("TLS Check: $line", M_DEBUG);
			
			#
			# This is a TLS result
			#
			
			my @versionInfo = split("v", $line);	# xxx, TLSvyyy
			my $version = $versionInfo[-1];
			
			my $ok = true;

			if (OpsB::Common::MyCompare($version, $TLSVersionMin) == -1) {
				$ok = false;
			}
			
			if ($line =~ /Server/i) {
				$msg = "Server TLS version: $version";
				($showMessage, $gotServer) = (true, true);
			}
			else {
				$msg = "This client TLS version: $version";
				$showMessage = $ARG_Client;
			}
			
			my $sev = M_OK;
			
			if ($ok == true) {
				$msg .= " which is supported in OBM version $ThisVersionExternal";
			}
			else {
				$msg .= " and must be upgraded to at least version $TLSVersionMin before upgrading to OBM version $ThisVersionExternal";
				$sev = M_ERROR;
			}
			
			if ($showMessage == true) {
				WO($msg, $sev);
				if ($sev != M_OK) {$showRecommended = true;}
			}
			
		}
		
	}
	
	if ($gotServer == false) {
		WO("The TLS information for the taget server was not found, make sure the correct target was used", M_ERROR);
	}
	else {
		
		if ($showRecommended == true) {
			WO("It is recommended that TLS version $TLSVersionRecommended is implemented for use with OBM version $ThisVersionExternal", M_INFO);
		}
		
	}
	
	WO("ProcessOutput: End", M_DEBUG);
} #P rocessOutput

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
	
	$ARG_Target = OpsB::Common::FindArg("target");
	$ARG_Client = OpsB::Common::FindSwitch("client");
	
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
	
	if (length($ARG_Target) == 0) {
		$error = "The LDAP target must be provided";
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
	
	WO("  -target <host>\tThe host (and optionally port) of the server to check for the TLS version");
	WO("  -client\t\tSwitch - enable check for client TLS version");
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