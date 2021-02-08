#!/usr/bin/perl

# ++
# File:     		obm-server-checks.pl
# Created:  		19-Aug-2020, by Andy
# Reason:   		Check to make sure server resources are sufficent (mainly for install)
# --
# Abstract: 		Part of db-tools, separated the server checks from the database checks
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#			Andy	19-Aug-2020	Created
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

our $Topaz = TopazDir();

#
# required
#

our $scriptVersion = "2.2";
our $scriptArgs = "size,type,nodisk,nomem,home,install,data,temp";

our ($useSettings, $settingsData, $settingsError) = (false, "", "");
our $settingsFile = OpsB::Common::GetScriptDir($0) . "settings.dat";
if (-e $settingsFile) {($useSettings, $settingsData, $settingsError) = OpsB::Common::ReadFileToString($settingsFile);}

our $OBMVersion = "";

if ($useSettings == true) {
		my $line = OpsB::Common::FindLineWithKey($settingsData, "<VersionInfo OBM");
		$OBMVersion = OpsB::Common::GetAttributeFromData($line, "Version");
}

#
# Additional
#

our $Size_Small = "Small";
our $Size_Medium = "Medium";
our $Size_Large = "Large";

our $Type_DPS = "DPS";
our $Type_GW = "Gateway";
our $Type_All = "All";

#
# Messages
#

our $MSG_MustChooseSomething = "\tBoth \"-nodisk\" and \"-nomem\" specified - this disables all checks";
our $MSG_InvalidSize = sprintf("\tAn invalid configuration size (%s) was specified. It must be one of \"%s\", \"%s\" or \"%s\"", "%s", $Size_Small, $Size_Medium, $Size_Large);
our $MSG_InvalidType = sprintf("\tAn invalid server type (%s) was specified. It must be one of \"%s\", \"%s\" or \"%s\"", "%s", $Type_All, $Type_DPS, $Type_GW);
our $MSG_Mem = "System Memory: %s (%s - Recommended: %s GB, Minimum: %s GB). ";
our $MSG_MemoryRequired = "Add more system memory to support this configuration";
our $MSG_MemoryAdvised = "Adding system memory will improve performance for this configuration";
our $MSG_MemoryOK = "The recommended memory requirements for this configuration have been met";
our $MSG_NoLocalDisks = "Unable to determine local disks, cannot continue processing";
our $MSG_DiskInfo = "Disk Free Space Checks:";
our $MSG_Windows_AllDisksOK = "All of the disks shown are eligable for the installation of OBM Version $OBMVersion";
our $MSG_Windows_SomeDisksWarn = "One or more disks shown do not have the optimal amount of free space for the installation of OBM Version $OBMVersion";
our $MSG_Windows_SomeDisksBad = "One or more disks shown do not have the enough free space for the installation of OBM Version $OBMVersion";
our $MSG_Linux_AllDisksOK = "All of the device locations shown are eligable for the installation of OBM Version $OBMVersion";
our $MSG_Linux_SomeDisksWarn = "One or more of the device locations shown do not have the optimal amount of free space for the installation of OBM Version $OBMVersion";
our $MSG_Linux_SomeDisksBad = "One or more of the device locations shown do not have the enough free space for the installation of OBM Version $OBMVersion";
our $MSG_MemoryTitle = "Memory Considerations for %s config (%s role):";
our $MSG_BadBSMData = "\tThe \"-home\" argument was specified, but one or more of \"-install\", \"-data\" or \"-temp\" is missing";

#
# Script Specific Arguments
#

our $ARG_ServerType = "";
our $ARG_Size = "";
our $ARG_NoDisk = false;
our $ARG_NoMem = false;
our $ARG_BSMHome = "";
our $ARG_BSMInstall = "";
our $ARG_BSMData = "";
our $ARG_Temp = "";

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
	
	my $argValues = "\n\t-home\t\t$ARG_BSMHome\n\t-install\t$ARG_BSMInstall\n\t-data\t\t$ARG_BSMData\n\t-temp\t\t$ARG_Temp\n";	
	OpsB::Common::ShowInputs($argValues);
	
	#
	# Show banner
	#
	
	my $additionalModules = sprintf("HPBSM Version: %s", HP_BSM_MODULE_VERSION);
	my $description = "Verify the server resources in preparation for installation of Operations Bridge Manager";
	my $title = "OBM Server System Resource Check";
	
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
	
	if ($ARG_NoMem == false) { GetMemoryInfo();}
	if ($ARG_NoDisk == false) {GetDiskInfo();}
	
	WO("ContinueScript: End", M_DEBUG);
} # ContinueScript

#
# Get Disk info which 
#

sub GetDiskInfo() {
	WO("GetDiskInfo: Start", M_DEBUG);
	
	#
	# First get the information on disk space requirements
	#
	
	my $platform = "Linux";
	if ($IsWindows == true) {$platform = "Linux";}
	
	my $keyTopaz = sprintf("<%s TopazDisk", $platform);
	my $keyInstall = sprintf("<%s InstallDisk", $platform);
	my $keyData = sprintf("<%s DataDisk", $platform);
	my $keyTemp = sprintf("<%s TempDisk", $platform);
	
	my $recommendedTopaz = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyTopaz)), "Recommended");
	my $minimumTopaz = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyTopaz)), "Minimum");
	
	my $recommendedInstall = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyInstall)), "Recommended");
	my $minimumInstall = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyInstall)), "Minimum");

	my $recommendedData = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyData)), "Recommended");
	my $minimumData = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyData)), "Minimum");

	my $recommendedTemp = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyTemp)), "Recommended");
	my $minimumTemp = OpsB::Common::GetAttributeFromData((OpsB::Common::FindLineWithKey($settingsData, $keyTemp)), "Minimum");

	#
	# On Windows you can place the data anywhere. So check all disks. Call out TEMP specifically
	#
	# On Linux we use /opt/HP/BSM, /opt/OV, /var and /tmp. So look at /opt /var and /tmp
	#
	# Put the information in a hash
	#

	my %diskChecks = ();
	
	#
	# If wwe have been told to use the HPBSM informatiom from a current install, then do so
	#
	
	if (length($ARG_BSMHome) > 0) {
		$diskChecks{$ARG_BSMHome} = sprintf("%s,%s,BSM Home (%s)", $recommendedTopaz, $minimumTopaz, $ARG_BSMHome);
		$diskChecks{$ARG_BSMInstall} = sprintf("%s,%s,Installation location (%s)", $recommendedInstall, $minimumInstall, $ARG_BSMInstall);
		$diskChecks{$ARG_BSMData} = sprintf("%s,%s,Data location (%s)", $recommendedData, $minimumData, $ARG_BSMData);
		$diskChecks{$ARG_Temp} = sprintf("%s,%s,Temp location (%s)", $recommendedTemp, $minimumTemp, $ARG_Temp);		
	}
	else {
		#
		# Not looking at the existing install, or there is no existing install
		#
		
		if ($IsWindows == true) {
			#
			# As potentially we can install any piece on any disk, the requirements are the sum of everything except temp. Only add temp if the disk has temp on it
			#
			
			my $recommendedTotal = $recommendedTopaz + $recommendedInstall + $recommendedData;
			my $minimumTotal = $minimumTopaz + $minimumInstall + $minimumData;
			
			#
			# Get all local drives as any of these could be used
			#
			
			my $localDisks = OpsB::Common::GetWindowsLocalDrives();
			
			if (length($localDisks) == 0) {
				WO($MSG_NoLocalDisks, M_ERROR);
				return;
			}
			
			#
			# Now get the TempDB drives
			#
			
			my $tempLocation = (split(':', (OpsB::Common::ExpandEnv("%TEMP%"))))[0] .":";
			
			#
			# Add to hash table
			#
			
			my @data = split(chr(10), $localDisks);
			
			foreach my $disk(@data) {			
				my $diskInfo = "";
				my ($recommended, $minimum) = ($recommendedTotal, $minimumTotal);
				
				if (lc $disk eq lc $tempLocation) {
					$diskInfo = "Potential install target and temp location";
					$recommended += $recommendedTemp;
					$minimum += $minimumTemp;
				}
				else {
					$diskInfo = "Potential install target";
				}
				
				$diskChecks{$disk} = sprintf("%s,%s,%s", $recommended, $minimum, $diskInfo);
			}
			
		} # Windows
		else {
			#
			# Linux is more strict (less flexible)
			#
			
			my $optRecommend = $recommendedTopaz + $recommendedInstall;
			my $optMinimum = $minimumTopaz + $minimumInstall;
			
			$diskChecks{"/opt"} = sprintf("%s,%s,Home and Installation location (/opt)", $optRecommend, $optMinimum); # /opt/OV may not exists as it may not be installed
			$diskChecks{"/var"} = sprintf("%s,%s,Data location (/var)", $recommendedData, $minimumData);
			$diskChecks{"/tmp"} = sprintf("%s,%s,Temp location (/tmp)", $recommendedTemp, $minimumTemp);
		}

	}
	
	#
	# Now check the drives we found - especially for Linux, we may find that a single root contains multiple partitions, 
	# so we will need to add them up if that is the case
	#
	
	my %finalDiskInformation = ();
	
	foreach my $disk (keys %diskChecks) {
		my @information = split(/,/, $diskChecks{$disk});		
		my ($recommended, $minimum, $diskInfo) = ($information[0], $information[1], $information[2]);
		
		#
		# Get the free space information
		#
		
		my ($diskSize, $diskFree, $diskRoot) = OpsB::Common::GetDiskSizeInfo($disk);
		my ($diskSizeDispay, $diskFreeDisplay) = (OpsB::Common::MakeGB($diskSize / (1024 * 1024)), OpsB::Common::MakeGB($diskFree / (1024 * 1024)));
		my ($diskSizeNumeric, $dummyA) = OpsB::Common::MakeStringNumeric($diskSizeDispay);
		my ($diskFreeNumeric, $dummyB) = OpsB::Common::MakeStringNumeric($diskFreeDisplay);
		
		if (!(defined $finalDiskInformation{$diskRoot})) {
			#
			# New information
			#
			
			$finalDiskInformation{$diskRoot} = sprintf("%s,%s,%s,%s,%s", $diskSizeNumeric, $diskFreeNumeric, $recommended, $minimum, $diskInfo);
		}
		else {
			#
			# Update the information regarding min and recommended (size and free remains the same)
			#
			
			my @values = split(/,/, $finalDiskInformation{$diskRoot});
			my ($thisSize, $thisFree, $thisRecommended, $thisMinimum, $thisInfo) = ($values[0], $values[1], $values[2], $values[3], $values[4]);
			
			#
			# Add up min and recommended requirements, and add new disk info
			#
			
			$recommended += $thisRecommended;
			$minimum += $thisMinimum ;
			$diskInfo .= sprintf("!%s", $thisInfo);
			
			#
			# Update
			#
			
			$finalDiskInformation{$diskRoot} = sprintf("%s,%s,%s,%s,%s", $diskSizeNumeric, $diskFreeNumeric, $recommended, $minimum, $diskInfo);
		}
		
	}
	
	#
	# OK - now we have a hash that has the information we need to check each disk for whether it matches or not.
	#
	
	my $csvData = "Location,Capacity,Free Space,Recommended Free,Minimum Free,Explanation,Information,Sev";
	my ($runningTotal, $nothingGood) = (M_OK, M_ERROR);
	
	foreach my $diskRoot(sort keys %finalDiskInformation) {
		my @values = split(/,/, $finalDiskInformation{$diskRoot});
		my ($thisSize, $thisFree, $thisRecommended, $thisMinimum, $thisInfo, $explanation) = ($values[0], $values[1], $values[2], $values[3], $values[4], "OK");
		
		#
		# Now we can check the available space...
		#
		
		my $sev = M_OK;
		
		if ($thisFree < $thisRecommended) {
			$sev = M_WARN;
			$explanation = "Below Recommended";
			if ($runningTotal < M_WARN) {$runningTotal = M_WARN;}
		}
		
		if ($thisFree < $thisMinimum) {
			$sev = M_ERROR;
			$explanation = "Below Minimum";
			if ($runningTotal < M_ERROR) {$runningTotal = M_ERROR;}
		}
		
		my $ctr = 0;
		
		foreach my $item((split(/!/, $thisInfo))) {
			
			if ($ctr > 0) {
				#
				# Don't need the specific information on free/size etc
				#
				
				($diskRoot, $thisSize, $thisFree, $thisRecommended, $thisMinimum, $explanation) = ("", "", "", "", "", "");
			}
			else {
				#
				# For display purposes
				#
				
				$thisSize .= " GB";
				$thisFree .= " GB";
				$thisMinimum .= " GB";
				$thisRecommended .= " GB";
			}
			
			$csvData .= sprintf("\n%s,%s,%s,%s,%s,%s,%s,%s", $diskRoot, $thisSize, $thisFree, $thisRecommended, $thisMinimum, $explanation, $item, $sev);
			$ctr +=1;
		}
		
	}
	
	#
	# Output
	#
	
	WO("");	
	WO($MSG_DiskInfo, M_INFO);
	WO("");
	OpsB::Common::CSVToTable($csvData, ",", false, true);
	WO("");
	
	my $finalMessage = "";
	
	if ($IsWindows == true) {
		#
		# A summary
		#
		
		if ($runningTotal == M_OK) {
			$finalMessage = $MSG_Windows_AllDisksOK;
		}
		
		if ($runningTotal == M_WARN) {
			$finalMessage = $MSG_Windows_SomeDisksWarn;
		}
		
		if ($runningTotal == M_ERROR) {
			$finalMessage = $MSG_Windows_SomeDisksBad;
		}
		
	}
	else {
		#
		# Sumamry on Linux
		#
		
		if ($runningTotal == M_OK) {
			$finalMessage = $MSG_Linux_AllDisksOK;
		}
		
		if ($runningTotal == M_WARN) {
			$finalMessage = $MSG_Linux_SomeDisksWarn;
		}
		
		if ($runningTotal == M_ERROR) {
			$finalMessage = $MSG_Linux_SomeDisksBad;
		}
		
	}
	
	WO($finalMessage, $runningTotal);
	WO("");
	
	WO("GetDiskInfo: End", M_DEBUG);
} # GetDiskInfo
#
# Get the memory information
#

sub GetMemoryInfo() {
	WO("GetMemoryInfo: Start", M_DEBUG);
	
	#
	# Get memory and then adjujst the result for display
	#
	
	my ($totalMemory, $availMemory) = OpsB::Common::GetSystemMemoryMB();
	my ($totalDisp, $availDisp) = (OpsB::Common::MakeGB($totalMemory), OpsB::Common::MakeGB($availMemory));
	my ($numericMem, $dummyMem) = OpsB::Common::MakeStringNumeric($totalDisp); # For comparison
	
	my $memData = "System Memory,Free,Minimum,Recommended,Explanation,sev";
	
	#
	# Figure out what our settings should be. The keys are in the config file for server type (Single/DPS/GW) and size (small/med/large)
	#
	
	my $key = sprintf("<Memory Size=\"%s\"", $ARG_Size);
	my $data = OpsB::Common::FindLineWithKey($settingsData, $key);
	
	my ($minimum, $recommended, $serverType) = ("MinimumDPS", "RecommendedDPS", "Data Processing Server");
	if ($ARG_ServerType eq $Type_GW) {($minimum, $recommended, $serverType) = ("MinimumGW", "RecommendedGW", "Gateway Server");}
	if ($ARG_ServerType eq $Type_All) {($minimum, $recommended, $serverType) = ("MinimumSingle", "RecommendedSingle", "Single Server");}
	
	my $minMem = OpsB::Common::GetAttributeFromData($data, $minimum);
	my $recommendedMem = OpsB::Common::GetAttributeFromData($data, $recommended);
	
	my $sev = M_ERROR;
	my $msg = sprintf($MSG_Mem, $totalDisp, $serverType, $recommendedMem, $minMem);
	
	if ($minMem > $numericMem) {
		$sev = M_ERROR;
		$msg = sprintf($MSG_MemoryRequired);
	}
	if (($numericMem > $minMem) && ($recommendedMem > $numericMem)) {
		$sev = M_WARN;
		$msg = sprintf($MSG_MemoryAdvised);
	}
	if ($numericMem >= $recommendedMem) {
		$sev = M_OK;
		$msg = sprintf($MSG_MemoryOK);
	}
	
	$memData .= sprintf("\n%s,%s,%s GB,%s GB,%s,%s", $totalDisp, $availDisp, $minMem, $recommendedMem, $msg, $sev);

	my $display = $ARG_ServerType;
	
	if ($ARG_ServerType eq $Type_All) {
		#
		# Show DPS and GW rather than "all"
		#
		
		$display = sprintf("%s and %s", $Type_DPS, $Type_GW);
	}
	
	WO(sprintf($MSG_MemoryTitle, $ARG_Size, $display), M_INFO);
	WO("");
	
	OpsB::Common::CSVToTable($memData, ",", false, true);		
	WO("GetMemoryInfo: End", M_DEBUG);
} #GetMemoryInfo

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
	
	$ARG_ServerType = OpsB::Common::FindArg("type");
	$ARG_Size = OpsB::Common::FindArg("size");
	$ARG_NoDisk = OpsB::Common::FindSwitch("nodisk");
	$ARG_NoMem = OpsB::Common::FindSwitch("nomem");
	$ARG_BSMHome = OpsB::Common::FindArg("home");
	$ARG_BSMInstall = OpsB::Common::FindArg("install");
	$ARG_BSMData = OpsB::Common::FindArg("data");
	$ARG_Temp = OpsB::Common::FindArg("temp");
	
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
		
	if ($ARG_NoDisk == true && $ARG_NoMem == true) {
		#
		# Can't do nothing...
		#
		
		$error = OpsB::Common::AddString($error, $MSG_MustChooseSomething, "\n");
		$ok = false;
	}

	if (length($ARG_BSMHome) > 0) {
		#
		# Have one - we need all
		#
		
		if ((length($ARG_BSMInstall) == 0) || (length($ARG_BSMData) == 0) || (length($ARG_Temp) == 0)) {
			$error = OpsB::Common::AddString($error, $MSG_BadBSMData, "\n");
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

	WO(sprintf("  -type <type>\t\tRole the server will have (one of \"%s\", \"%s\" or \"%s\")", $Type_All, $Type_DPS, $Type_GW)); 
	WO(sprintf("  -size <size>\t\tConfiguration size (one of \"%s\", \"%s\" or \"%s\")", $Size_Small, $Size_Medium, $Size_Large));
	WO("  -nodisk\t\tDisable disk checks");
	WO("  -nomem\t\tDisable memory checks");
	
	OpsB::Common::CommonHelp();
	

}

#
# Display help for this routines
#
############################################################################################################################################################################
# Start here
############################################################################################################################################################################

Main();