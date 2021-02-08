#!/usr/bin/perl

# ++
# File:     		run-content-manager.pl
# Created:  		15-May-2020, by Andy
# Reason:   		Run Content Manager to return a list of installed content packs
# --
# Abstract: 		List the installed content packs, allowing filters for Management packs
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	15-May-2020	Created
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

use OpsB::OVDeploy;
use OpsB::OVDeploy qw(OV_VERSION $OVDeploy $OprAgt $Dummy_Win $Dummy_Unix);

our $HPBSM_Module_Version = OpsB::HPBSM::HP_BSM_MODULE_VERSION;

#
# required
#

our $scriptVersion = "2020.12";
our $scriptArgs = "input,user,pwd,cp,mp,cnx";

#
# Messages
#

our $MSG_ContentCommandReturnedNothing = "No information was returned from the command to retireve Content Pack information";
our $MSG_MPGeneric = "Management Pack: %s Version: %s";
our $MSG_MPOK = "Management Pack: %s Version: %s is the current version";
our $MSG_MPWarn = "Management Pack: %s Version: %s should be upgraded to version: %s";
our $MSG_MPError = "Management Pack: %s Version: %s is lower than the supported version: %s and should be upgraded to version: %s";

our $MSG_CNXOK = "%s Version: %s is the current version";
our $MSG_CNXWarn = "%s Version: %s should be upgraded to version: %s";
our $MSG_CNXError = "%s Version: %s is lower than the supported version: %s and should be upgraded to version: %s";
		 
#
# Script Specific Arguments
#

our $ARG_Input = "";
our $ARG_User = "";
our $ARG_PWD = "";
our $ARG_MP = false;
our $ARG_CP = false;
our $ARG_Connector = false;

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
	
	#
	# Show banner
	#
	
	my $additionalModules = sprintf("HPBSM Version: %s, OVDeploy: %s", $HPBSM_Module_Version, OpsB::OVDeploy::OV_VERSION); # sprintf("DB Version: %s, XYZ Version: %s", $modDB_Version, $modXYZ_Version);
	OpsB::Common::SayHello($scriptVersion, $additionalModules, "Execute HPBSM ContentManager utility"); # ScriptVersion, AdditionalModules, Specific Description 
	
	WO("Main: Start", M_DEBUG);
	
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
		
		my $util = $topaz . OpsB::HPBSM::ContentManager_Unix;
		if ($IsWindows == true) {$util = $topaz . OpsB::HPBSM::ContentManager_Win;}
		
		if (-e $util) {
			#
			# Utility exists, so run it
			#
			
			my $cmd = sprintf("\"%s\" -list -user \"%s\" -pw \"%s\" -verbose", $util, $ARG_User, $ARG_PWD);
			
			my ($cmdOK, $rc, $stdout, $stderr) = OpsB::Common::RunCommandTimeout($cmd, "OBM Content Manager");
			
			if (($cmdOK == false) || ($rc != 0)) {
				
				if ($rc == OpsB::Common::CMD_TimeoutCode) {
					#
					# If it timed out there may still be data
					#
					
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
					
					WO($MSG_ContentCommandReturnedNothing, M_ERROR);
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
		ProcessDataMP($data);
		ProcessDataCP($data);
		ProcessDataConnector($data);
	}

	
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Get MP Information
#

sub ProcessDataMP() {
	my $data = shift;
	my $msg = "";
	
	if ($ARG_MP == false) {
		return;
	}
	
	WO("ProcessDataMP: Start", M_DEBUG);

	my %hashData = OpsB::HPBSM::ParseContentPacks($data, $ARG_MP);
	
	#
	# Read the results
	#
	
	 my @products = keys %hashData;
	 my @versions = values %hashData;
	 
	 foreach my $i(0..$#products) {
		 my $product = $products[$i];
		 my $version = $versions[$i];
		 
		 WO("Product: $product, version: $version", M_DEBUG);
		 
		 #
		 # Some have underscores
		 #
		 
		 $product =~ s/_/ /g;
		 $product =~ s/^OBM Management Pack for //gi;
		 $product =~ s/^OMi Management Pack for //gi;
		 
		 my $sev = M_INFO;
		 $msg = sprintf($MSG_MPGeneric, $product, $version);
		 		 
		 if ($useVersion == true) {
			my $key = sprintf("<ManagementPack Name=\"%s\"", $product);
			my ($recommended, $lowest) = OpsB::HPBSM::MPVersions($version_data, $key);
							
			if (OpsB::Common::MyCompare($version, $recommended) == -1) {
				#
				# Needs an upgrade, but by how much?
				#
				
				$msg = sprintf($MSG_MPWarn, $product, $version, $recommended);
				$sev = M_WARN;
				
				if (length($lowest) > 0) {
					$msg = sprintf($MSG_MPWarn, $product, $version, $recommended);
					$sev = M_WARN;
					
					if (OpsB::Common::MyCompare($version, $lowest) == -1) {
						$msg = sprintf($MSG_MPError, $product, $version, $lowest, $recommended);
						$sev = M_ERROR;
					}
				}
				
			}
			else {
				$msg = sprintf($MSG_MPOK, $product, $version);
				$sev = M_OK;
			} # Compare version
			
		 } # Use Version info
		 
		 WO($msg, $sev);
	 }
	 
	WO("ProcessDataMP: End", M_DEBUG);
} #ProcessDataMP

#
# Get MP Information
#

sub ProcessDataCP() {
	my $data = shift;
	my ($msg, $sev) = ("", M_INFO);
	
	if ($ARG_CP == false) {
		return;
	}
	
	#
	# Not yet implemented
	#
	
	return;
	
	WO("ProcessDataCP: Start", M_DEBUG);

	my %hashData = OpsB::HPBSM::ParseContentPacks($data, false, true);
	
	#
	# Read the results
	#
	
	 my @products = keys %hashData;
	 my @versions = values %hashData;
	 
	 foreach my $i(0..$#products) {
		 my $product = $products[$i];
		 my $version = $versions[$i];
		 
		 WO("Product: $product, version: $version", M_DEBUG);
		 		 
		 WO($msg, $sev);
	 }
	 
	WO("ProcessDataCP: End", M_DEBUG);
} #ProcessData

#
# Get Connector Information
#

sub ProcessDataConnector() {
	my $data = shift;
	my ($msg, $sev) = ("", M_INFO);
	
	if ($ARG_Connector == false) {
		return;
	}
		
	WO("ProcessDataConnector: Start", M_DEBUG);

	my %hashData = OpsB::HPBSM::ParseContentPacks($data, false, false, true);
	
	#
	# Read the results
	#
	
	#my @products = keys %hashData;
	#my @versions = values %hashData;
	 
	#foreach my $i(0..$#products) {
	foreach my $product(sort keys %hashData) {
		#my $product = $products[$i];
		my $version = $hashData{$product}; #$versions[$i];

		#
		# Manipulate the data#
		#
		
		$product =~ s/^OBM_/Operations/;	# for OBM_Connector for...
		$product =~ s/^obm_//;	# for obm_opscx....
		$product =~ s/^OperationsConnector/Operations Connector/;	# Yes... this happens
		$product =~ s/opscx for/Operations Connector for/ig;
		$product =~ s/opscx/Operations Connector for/ig;
		$product =~ s/^OBM //;
		$product =~ s/^Connector/Operations Connector/;
		$product =~ s/_/ /g;
		
		$version =~ s/\(//g;
		$version =~ s/\)//g;	
			
		WO("Product: $product, version: $version", M_DEBUG);

		my $recommended = OpsB::OVDeploy::GetRecommendedVersion($product, $version_data, "\<ContentPack");							
		my $sev = M_INFO;
		
		if ($product =~ /Genint/i) {$product = "Generic Integration Framework"; }	# "Special"
		my $msg = sprintf("%s version: %s", $product, $version);
				
		if (length($recommended) > 0) {
			
			if (OpsB::Common::MyCompare($version, $recommended) == -1) {
				$sev = M_WARN;
				$msg .= " which is lower than the recommended version: $recommended";
			}
			else {
				$sev = M_OK;
				$msg .= " which is the recommended version";
			}
			
		}	
		
		WO($msg, $sev);	
	}
	 
	WO("ProcessDataConnector: End", M_DEBUG);
} #ProcessDataConnector
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
	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_PWD = OpsB::Common::FindArg("pwd");
	$ARG_MP = OpsB::Common::FindSwitch("mp");
	$ARG_CP = OpsB::Common::FindSwitch("cp");
	$ARG_Connector = OpsB::Common::FindSwitch("cnx");
	
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
		
	if ((defined $ARG_Input) && (length($ARG_Input) > 0)) {
		#
		# Input file specified (which means "offline mode", so check it exists
		#
		
		if (!(-e $ARG_Input)) {
			$error = OpsB::Common::AddString($error, sprintf("The input file \"%s\" is missing", $ARG_Input), "\n");
			$ok = false;
		}
		
	}
	else {
		#
		# Need a user & password
		#
		
		if (length($ARG_User) == 0) {$ARG_User = "admin";} # Default to this user
		
		if (length($ARG_PWD) == 0) {
			$error = OpsB::Common::AddString($error, sprintf("The password for user %s cannot be blank", $ARG_User), "\n");
			$ok = false;
		}
		
	}
	
	if (($ARG_CP == false) && ($ARG_MP == false) && ($ARG_Connector == false)) {
		$error = OpsB::Common::AddString($error, "At least one of \"cnx\", \"-mp\" or \"-cp\" must be specified", chr(10));
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
	
	WO("  -input <file>\t\tInput file if processing in offline mode");
	WO("  -user <user>\t\tThe username for connecting to the OBM/OMi gateway server (default is \"admin\"");
	WO("  -pwd <password>\tThe password for the specified user");
	WO("  -cp\t\t\tShow Content Packs");
	WO("  -mp\t\t\tShow Management Packs");
	WO("  -cnx\t\tShow Connectors");
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