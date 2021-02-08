#!/usr/bin/perl

# ++
# File:     run-obr-checks.pl
# Created:  Apr-2020, by Andy
# Reason:   Operations Bridge Version Checks
# --
# Abstract: This script acts as the "driver" for other utilities
#
#           On Linux, the script should just be invoked. On Windows, a perl engine is required. Either something like ActivePerl, or the 
#           perl engin included with an OpsBridge Agent.
#
#           If the perl engine from OpsBridge is used, this script can be invoked using the "oaperl.bat" batch file
# --
# Edit History:
#
#           Who     When        Why
#           ======= =========== =================================================================================================================
#           Andy    20-Apr-2020	Created
#			Andy	29-Jun-2020	Version 2 update
# --

use strict;
use warnings;

# To add the OpsB Common utilities need to add the directory to @INC
#

use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(abs_path $0) . '/lib'; # Utilies pm files below here
use OpsB::Common; # Holds a number of routines, most we will access with the full name but better top use the short name for some
use OpsB::Common qw(WO true false $IsWindows M_NONE M_INFO M_OK M_WARN M_ERROR M_FATAL M_DEBUG $ARG_Debug $ARG_Log $ARG_Color $ARG_Quiet $ARG_Timeout $ARG_NoWelcome $ARG_Help $MF_UTIL) ; 

use OpsB::Compress;

#
# Version of this script
#

our $myVersion = "2020.12";
our $zipScriptVersion = OpsB::Compress::COMPRESS_VERSION;
our $TopLevel = OpsB::Common::GetTempDir();

#
# Suppoerted inouts
#

our $ARGS_Supported = "user,pwd,host,input,keep,verbose";

#
# Used in this script to "find" other script files
#

our $scriptDir = dirname(abs_path $0);

our $MSG_InvalidArgs = OpsB::Common::MSG_BadArgs;
our $MSG_RunCommand = OpsB::Common::MSG_RunCommand;
our $MSG_RunCommand_Timeout = OpsB::Common::MSG_RunCommandTimeout;
our $MSG_TimeTaken = OpsB::Common::MSG_CommandRunTime;

our $MSG_Extracting = "Extracting zipped files ...";
our $MSG_Cleaning = "Removing temporary files ...";
our $MSG_NoOBR = "This server does not have OBR installed, please run the script on an OBR server or manually capture the logs and re-run specifying the output zip file";
our $MSG_CWDFail = "Unable to set current location to the directory containing the capture tool\nTarget: %s\nActual: %s";
our $MSG_NoCaptureFile = "The output file %s was not created, make sure the capture tool is correctly installed";
our $MSG_NoCaptureFile_Verbose = "The output file %s was not created, make sure the capture tool is correctly installed. Full error:\n\n%s\n";
our $MSG_NoCaptureTool = "The capture tool was not found, please install this to continue. Checked in location:\n\t%s";
our $MSG_Header = "Analysis for %s server %s with Vertica Server: %s";
our $MSG_VersionInfo = "OBR Version information ...";
our $MSG_SystemInfo = "System Information ...";
our $MSG_CMDBInfo = "CMDB Information ...";
our $MSG_ContentPackInfo = "Content packs ...";
our $MSG_SummaryInfo = 	"In the information above, if a Content Pack is shown as \"INFO\" then there has been no version check made. Check online for more details:\n\n\thttps://docs.microfocus.com/itom/Operations_Bridge:Content/Home\n";
our $MSG_CPVersionFileInfo = "The definition file used for checking Content Pack versions is: %s";
our $MSG_FailedToProcessFile = "Unable to process file %s";
our $MSG_FileNotFound = "The configuration file %s was not found in the capture";
our $MSG_CMDBMessage = "CMDB Server: %s, port: %s. Accessed via user: %s";
our $MSG_OSMsg = "%s Version: %s";
our $MSG_DiskMsg = "%s - Total Size: %s, Free Space: %s";
our $MSG_OSSummaryMSG = "Server: %s, %s, %s memory";
our $MSG_DiskFinalMSG = "Local Disk Information:\n\t%s";
our $MSG_DiskMsgUnix = "\tDisk: %s, size: %s";		
our $MSG_NoContentPacks = "Unable to locate Content Pack Version information, continuing without checks";
our $MSG_CPRecommended = "%s, Version: %s - recommended version: %s";
our $MSG_CPNoRecommndation = "%s, Version: %s";
our $MSG_BSM_NeedsUpgrade = "Package %s, Version: %s with Patch: %s. Release State: %s - this needs to be upgraded to Version: %s";
our $MSG_BSM_NoUpgrade = "Package %s, Version: %s with Patch: %s. Release State: %s";

#
# The information that we are looking for in the zip files
#

our $CMDBInfo = "Datasource";
our $SysInfo = "SystemInformation";
our $BSMRInfo = "SHR_application_configuration";
our $ContentInfo = "installed_cp";
our $ConfigInfo = "SHR_application_configuration";

our $CMDBFile = "dict_cmdb_ds.csv";
our $SysFile = "systemPropertiesInfo.csv";
our $BSMRFile = "BSMRversion.prp";
our $ContentFile = "Installed_Content_Packs.csv";
our $ConfigFile = "config.prp";

#
# Constants
#

#our $BSM_Home_Unix => "$PMDB_HOME";
our $PMDB_Home = "%PMDB_HOME%";
our $PMDB_UtilDir = "/contrib/Supportability/capture_tool/perl/";
our $PMDB_CaptureOut = "/capturetool_output/";
our $PMDB_Util = "capturetool.sh";

#
# Input arguments
#

our $ARG_ZipFile = "";
our $ARG_Keep = false;
our $ARG_Verbose = false;
our $HostOS = "";
our $Host = "";
our $VerticaHost = "";

our $CMDB = "";

our $SystemInfo = "";
our $DiskInfo = "";

our $OBRInfo = "";
our $OBRSev = M_OK;

our $ContentPackInfo = "";

our $CPVersions = OpsB::Common::VERSIONS_FILE; #"obr-cp-versions.dat";
#
# For version information
#

our ($useVersion, $version_data, $versionError) = (false, "", "");
our $versionsFile = OpsB::Common::GetScriptDir($0) . OpsB::Common::VERSIONS_FILE;
if (-e $versionsFile) {($useVersion, $version_data, $versionError) = OpsB::Common::ReadFileToString($versionsFile);}

#
# Start here
#

sub Main() {
	#
	# Check the support utility exists first!
	#
	
	if (!(-e $MF_UTIL)) {
		OpsB::Common::WO(sprintf(OpsB::Common::MSG_UtilMissing, $MF_UTIL), M_FATAL);
		return;
	}

    #
    # Get input args and switches
    #

    GetInputs();
	
	WO("Start: Main", M_DEBUG);
	
    #
    # Announce we are here
    #

	my $otherModules = "Compress Version: $zipScriptVersion";
    my $useLog = OpsB::Common::SayHello($myVersion, $otherModules, "Utility to analyze OBR server information" );

    if ($ARG_Help == true) {
        ShowHelp();
        return;
    }

	#
	# Show the inputs
	#
	
	#my $inputs = "inputs:\n  zip file:\t$ARG_ZipFile";
	#WO($inputs, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Verbose);
	
    #
    # Validate the inputs, quit if bad
    #

	my ($inputOK, $inputError) = CheckInputs();
	
    if ($inputOK == false) {
		ShowHelp();
		WO($inputError, M_ERROR);
        return;
    }

    #
    # Check we got no invalid inputs
    #
    
    my ($argsOK, $badList) = OpsB::Common::ValidateArgs($ARGS_Supported);

    if ($argsOK == false) {
        ShowHelp();
        my $msg = sprintf($MSG_InvalidArgs, $badList);
        WO($msg, M_FATAL);
        return;
    }

	ProcessData();
	#system("curl -uadmin:admin \"http://catvmapm950.ftc.hpeswlab.net:29000/invoke?operation=displayDeploymentReport&objectname=BSM-Platform%3Aservice%3DBSMServerDeployment\"");
	WO("End: Main", M_DEBUG);
}

#
# Do the work
#

sub ProcessData() {
	WO("Start: ProcessData", M_DEBUG);
	
	if (length($ARG_ZipFile) == 0) {
		$ARG_ZipFile = GetZipFile();
		
		if (length($ARG_ZipFile) == 0) {
			return;
		}
		
	}
	
	WO($MSG_Extracting, M_INFO);

	my ($ok, $error) = OpsB::Compress::UnZip($ARG_ZipFile, $TopLevel);
	
	if ($ok == true) {
		ProcessUnzippedParent($TopLevel);
		
		if ($ARG_Keep == false) {
			WO($MSG_Cleaning, M_INFO);
			OpsB::Common::KillDir($TopLevel);
		}
		
	}
	else {
		WO($error, M_WARN);
	}

	WO("End: ProcessData", M_DEBUG);
}

#
# See if we can run the capture tool live
#

sub GetZipFile () {
	WO("Start: GetZipFile", M_DEBUG);
	
	#
	# This means we will run the script, so make sure that it can be located
	#
	my ($zip, $msg) = ("", "");
	my $actualDir = OpsB::Common::ExpandEnv("$PMDB_Home");

	if (index($actualDir, "%") > -1) {
		WO($MSG_NoOBR, M_FATAL);
	}
	else {
		my $CMD = $PMDB_Util;
		
		if ($IsWindows == true) {
			$CMD =~ s/.sh/.bat/g;
		}
		
		my $cmdLocation = $actualDir . $PMDB_UtilDir;
		my $outputLocation = $actualDir . $PMDB_CaptureOut;
		my $cmdToRun = $cmdLocation . $CMD;
		
		if (-e $cmdToRun) {
			#print("==> Run: $cmdToRun\nIn Location: $cmdLocation\n");
			#
			# We have to be in the same dir as the tool to run it, so find out what the cwd is so we can step back later
			#
			
			my $cwd = OpsB::Common::GetCWD();
			
			if ($IsWindows == true) {
				$cmdLocation =~ s/\//\\/g;
			}
			
			chdir $cmdLocation;
			my $new = OpsB::Common::GetCWD();
			
			if ($new ne $cmdLocation) {
				$msg = sprintf($MSG_CWDFail, $new, $cmdLocation);
				WO($msg, M_FATAL);
			}
			else {
				#
				# We are in the correct location so now execute the command
				#
				
				my ($ok, $retCode, $stdout, $stderr) = OpsB::Common::RunCommandTimeout($cmdToRun, "OBR Capture tool");
				#print("==> OK: $ok\n==> out: $stdout\n==> err: $stderr\n==>ret: $retCode\n");
				
				my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();

				my $fileDate = sprintf("%d%02d%02d", (1900 + $year), (1 + $mon), $mday); # year is from 1900, month is from 0
				my $fileName = $outputLocation . "capture_output_$fileDate.zip";
				
				if (-e $fileName) {
					$zip = $fileName;
					
					if ($IsWindows == true) {
						$zip =~ s/\//\\/g;
					}
				}
				else {
					#
					# The tool returns an OK (rc = 0) even if it fails. Give an option to show the full output as it's difficult
					# to read and also is returned as output, not an error
					#
					
					if ($IsWindows == true) {
						#
						# 2 substitutions as it seems we have something like c:\path/file
						#
						
						$fileName =~ s/\//\\/g; 
						$fileName =~ s/\\/\\\\/g;
					}
					
					$msg = sprintf($MSG_NoCaptureFile, $fileName);
					
					if ($ARG_Verbose == true) {
						my $errInfo = $stdout;
						if (length($stderr) > 0) {$$errInfo .= "\n$stderr";}
						$msg = sprintf($MSG_NoCaptureFile_Verbose, $fileName, $errInfo);
					}
					
					WO($msg, M_FATAL);
				}
				
				#
				# Change back
				#
				
				chdir $cwd;				
			}
		}
		else {
			$msg = sprintf($MSG_NoCaptureTool, $CMD);
			WO($msg, M_FATAL);
		}
	}

	WO("End: GetZipFile", M_DEBUG);
	
	return $zip;
}

#
# Go through each unzipped zip
#

sub ProcessUnzippedParent() {
	WO("Start: ProcessUnzippedParent", M_DEBUG);
	my $parent = shift;	
	my $zipParent = sprintf("%s/capture_output/", $parent);
	my $msg = "";
	
	if ($IsWindows == true) {
		#
		# Turn / into \ for later processing
		#
		
		$zipParent =~ s/\//\\/g;
	}
	
	my $fileList = sprintf("%s*.zip", $zipParent);
	my @files = glob($fileList);
	
	for my $file(@files) {
		WO("Checking file $file", M_DEBUG);
		
		if ($file =~ /$ConfigInfo/) {
			ProcessSubFile($file, $zipParent, $ConfigFile);
		}
		
		if ($file =~ /$SysInfo/) {
			ProcessSubFile($file, $zipParent, $SysFile);
		}

		if ($file =~ /$CMDBInfo/) {
			ProcessSubFile($file, $zipParent, $CMDBFile);
		}

		if ($file =~ /$BSMRInfo/) {
			ProcessSubFile($file, $zipParent, $BSMRFile);
		}

		if ($file =~ /$ContentInfo/) {
			ProcessSubFile($file, $zipParent, $ContentFile);
		}
	}
	
	my $header = sprintf($MSG_Header, $HostOS, $Host, $VerticaHost);
	WO($header, M_INFO);

	if (length($OBRInfo) > 0) {
		WO("");
		WO($MSG_VersionInfo, M_INFO);
		WO($OBRInfo, $OBRSev);
	}
	
	if (length($SystemInfo) > 0) {	
		WO("");
		WO($MSG_SystemInfo, M_INFO);
		WO($SystemInfo, M_INFO);
		
		if (length($DiskInfo) > 0) {
			WO($DiskInfo, M_INFO);
		}
	}
	
	if (length($CMDB) > 0 ) {
		WO("");
		WO($MSG_CMDBInfo, M_INFO);
		WO($CMDB, M_INFO);
	}
	
	if (length($ContentPackInfo) > 0) {
		WO("");	
		WO($MSG_ContentPackInfo, M_INFO);
		
		#
		# One line per CP which may have different severities per line, so is formatted as CP|sev,CP|sev,...,CP|several
		#
		
		my @CP = split('\*', $ContentPackInfo);

		for my $eachCP(@CP) {
			my @detail = split('\|', $eachCP);
			WO($detail[0], $detail[1]);
		}

		WO("");
		WO($MSG_SummaryInfo, M_INFO);
		$msg = sprintf($MSG_CPVersionFileInfo, $CPVersions);
		WO($msg, M_INFO);
	}
	
	WO("End: ProcessUnzippedParent", M_DEBUG);
}

sub ProcessSubFile () {
	WO("Start: ProcessSubFile", M_DEBUG);
	my ($zip, $parent, $file) = @_;
	my $msg = "";
	
	#
	# We know the filename ends in ".zip" so we are safe to just remove that to get the directory name. Found this can be too lok, so put
	# the extrcated files into the parent
	#
	
	my $zipDirectory = substr($zip, 0, (length($zip) -4));
	$zipDirectory = $TopLevel . "/" . substr($zipDirectory, length($parent), (length($zipDirectory) - length($parent)));
	
	if ($IsWindows == true) {
		$zipDirectory =~ s/\//\\/g;
	}
	
	#WO("Processing file: $zip into $zipDirectory", $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
	
	my ($ok, $error) = OpsB::Compress::UnZip($zip, $zipDirectory, $file);
	
	if ($ok == true) {
		#
		# Read the file if we can
		#
		
		my $readFile = $zipDirectory . "/" . $file;
		
		if ($IsWindows == true) {
			$readFile =~ s/\//\\/g;
		}
		
		if (-e $readFile) {
		
			my ($fileOK, $data) = OpsB::Common::ReadFileToString($readFile);
			
			if (length($data) == 0) {
				$msg = sprintf($MSG_FailedToProcessFile, $file);
				WO($msg, M_WARN);
			}
			else {
				
				if ($file eq $ConfigFile) {
					($HostOS, $Host, $VerticaHost) = ProcessConfigInfo($data);
				}
				
				if ($file eq $SysFile) {
					($SystemInfo, $DiskInfo) = ProcessSysInfo($data);
				}
				
				if ($file eq $BSMRFile) {
					($OBRInfo, $OBRSev) = ProcessBSMRData($data);
				}
				
				if ($file eq $ContentFile) {
					$ContentPackInfo = ProcessContent($data);
				}
				
				if ($file eq $CMDBFile) {
					$CMDB = ProcessCmdbInfo($data);
				}
				
			}
		}
		else {
			$msg = sprintf($MSG_FileNotFound, $file);
			WO($msg, M_WARN);
		}
	}
	else {
		WO($error, M_WARN);
	}
	
	WO("End: ProcessSubFile", M_DEBUG);
}

#
# Process config
#

sub ProcessConfigInfo() {
	WO("Start: ProcessConfigInfo", M_DEBUG);

	my $data = shift;
	my ($osType, $host, $verticaHost) = ("", "", "");
	#printf("==> $data\n");
	my $pos = index($data, "server.os.type");
	
	if ($pos > -1) {
		my $posEnd = index($data, chr(10), $pos);
		$osType = OpsB::Common::ElementFromSplit(substr($data, $pos, $posEnd - $pos), "=", -1);
		#printf("==> $osType <==\n");
	}

	$pos = index($data, "obr.rest.hostname");
	
	if ($pos > -1) {
		my $posEnd = index($data, chr(10), $pos);
		$host = OpsB::Common::ElementFromSplit(substr($data, $pos, $posEnd - $pos), "=", -1);
		#printf("==> $host <==\n");
	}
	
	$pos = index($data, "database.host");
	
	if ($pos > -1) {
		my $posEnd = index($data, chr(10), $pos);
		$verticaHost = OpsB::Common::ElementFromSplit(substr($data, $pos, $posEnd - $pos), "=", -1);
		#printf("==> $verticaHost <==\n");
	}
	
	WO("End: ProcessConfigInfo", M_DEBUG);
	return $osType, $host, $verticaHost;
}

#
# Process Sysinfo
#

sub ProcessCmdbInfo() {
	WO("Start: ProcessCmdbInfo", M_DEBUG);
	my $data = shift;
	my $msg = "";
	
	#
	# Pick up on install and uninstall
	#
	#printf("$data\n");
	
	my @allData = split(chr(10), $data);
	
	for my $line(@allData) {
		#
		# ds_cmdb_id,schedule_id, hostname,username,password,port,last_collection,connected_status,collection_status,enabled
		#
		
		my @lineData = split('\,', $line);
		my ($id, $sched, $host, $user, $port) = ($lineData[0], $lineData[1], $lineData[2], $lineData[3], $lineData[5]);
		
		if (!($id =~/ds_cmdb_id/)) {
			$id =~ s/\t//g;
			$host =~ s/\t//g;
			$user =~ s/\t//g;
			$port =~ s/\t//g;
		
			$msg = sprintf($MSG_CMDBMessage, $host, $port, $user);
			#WO($msg, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
		}
	}
	
	return $msg;
	WO("End: ProcessCmdbInfo", M_DEBUG);
}

#
# Process Sysinfo
#

sub ProcessSysInfo() {
	WO("Start: ProcessSysInfo", M_DEBUG);
	my $data = shift;
	my ($msg, $diskInfo) = ("", "");
	
	#
	# Pick up on install and uninstall
	#
	
	$data =~ s/\0//g;	# Windows appears to have nulls ...
	
	if ($data =~ /Win32/i) {
		($msg, $diskInfo) = ProcessSysInfoWin($data);
	}
	else {
		($msg, $diskInfo) = ProcessSysInfoLinux($data);
	}
	
	return $msg, $diskInfo;
	WO("End: ProcessSysInfo", M_DEBUG);
}

#
# Process Sysinfo
#

sub ProcessSysInfoWin() {
	WO("Start: ProcessSysInfoWin", M_DEBUG);
	my $data = shift;
	my $msg = "";
	
	#
	# Pick up on install and uninstall
	#
	
	#printf("$data\n");
	my @allData = split(chr(10), $data);
	my $OS = "";
	my $mem = "";
	my $node = "";
	my $diskInfo = "";

	my $max = scalar @allData;
	
	for (my $i = 0; $i < $max; $i ++) {
		my $line = $allData[$i];
		
		if ($line =~ /^OS Information/i) {
		
			if (($i + 4) < $max) {
				$i += 4;
				my @OSInfoLine = split('\,', $allData[$i]);
				
				$node = $OSInfoLine[0];
				
				$mem = $OSInfoLine[7];
				$mem =~ s/\"//g;
				$mem = OpsB::Common::MakeGB($mem /1024);
				$OS = sprintf($MSG_OSMsg, $OSInfoLine[1], $OSInfoLine[8]);
				$OS =~ s/\"//g;
			}
		}
		
		if ($line =~ /Local Fixed Disk/i) {
			#
			# Some data has commas in the quotes, so split on ," and then adjust
			#
			
			my @diskData = split("\,\"", $line);
			
			my $diskLabel = $diskData[1];
			$diskLabel =~ s/\"//g;
			
			my $diskFree = $diskData[4];
			$diskFree =~ s/\"//g;
			$diskFree =~ s/\,//g;
			$diskFree = OpsB::Common::MakeGB(($diskFree /1024) / 1024);
			
			my $diskTotal = $diskData[5];
			$diskTotal =~ s/\"//g;
			$diskTotal =~ s/\,//g;
			$diskTotal = OpsB::Common::MakeGB(($diskTotal /1024) /1024);

			my $thisDisk = sprintf($MSG_DiskMsg, $diskLabel, $diskTotal, $diskFree);
			
			if (length($diskInfo) == 0) {
				$diskInfo = $thisDisk;
			}
			else {
				$diskInfo .= "\n\t$thisDisk";
			}
		}
	}

	$msg = sprintf($MSG_OSSummaryMSG, $node, $OS, $mem);
	#WO($msg, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
	
	if (length($diskInfo) > 0) {
		$diskInfo = sprintf($MSG_DiskFinalMSG, $diskInfo);
		#WO($diskInfo, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Quiet);
	}
	
	return $msg, $diskInfo;
	WO("End: ProcessSysInfoWin", M_DEBUG);
}

#
# Process Sysinfo
#

sub ProcessSysInfoLinux() {
	WO("Start: ProcessSysInfoLinux", M_DEBUG);
	my $data = shift;
	my $msg = "";
	
	#
	# Pick up on install and uninstall
	#
		
	#printf("$data\n");
	my @allData = split(chr(10), $data);
	my $numCPU = 0;
	my $OS = "";
	my $mem = "";
	my $diskInfo = "";
	
	for my $line(@allData) {
		
		if ($line =~ /^Disk \//) {
			#
			# Disk <disk>: <size G/MB>, <size> bytes
			#
			
			my $diskData = substr($line, 5, length($line) -5);
			my $diskName = substr($diskData, 0, index($diskData, ":"));

			my $size = substr($diskData, index($diskData, ":") +2, index($diskData, ",") - (index($diskData, ":") +2));
			#$bytes =~ s/ //g;
			$msg = sprintf($MSG_DiskMsgUnix, $diskName, $size);
			
			if (length($diskInfo) == 0) {
				$diskInfo = $msg;
			}
			else {
				$diskInfo .= "\n$msg";
			}
			
		}
		
		if ($line =~ /^processor/) {
			$numCPU += 1;
		}
	
		if ($line =~ /^Operating System/) {
			$OS = substr($line, index($line, ",") + 2, length($line) - (index($line, ",") + 2));
		}
	
		if ($line =~ /^MemTotal/) {
			$mem = OpsB::Common::ElementFromSplit($line, ",", -1);
			$mem =~ s/ //g;
			$mem =~ s/kb//ig;
			$mem = OpsB::Common::MakeGB(($mem / 1024));
		}
	}
	
	$msg = "$OS, $numCPU CPUs and $mem memory";
	#WO($msg, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
	
	if (length($diskInfo) > 0) {
		$diskInfo = "Local Disk Information:\n$diskInfo";
		#WO($diskInfo, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
	}
	
	return $msg, $diskInfo;
	WO("End: ProcessSysInfoLinux", M_DEBUG);
}

#
# Process the content file
#

sub ProcessContent() {
	WO("Start: ProcessContent", M_DEBUG);
	my $data = shift;
	my $msg = "";
	my $returnInfo = "";
	my $sev = M_OK;
	
	if (length($version_data) == 0) {
		WO($MSG_NoContentPacks, M_WARN);
		$sev = M_INFO;
	}

	#
	# Pick up on install and uninstall
	#
	
	my @allData = split(chr(10), $data);
	
	for my $line(@allData) {
		#
		# CSV format is App,InstallDate,Version,Status,domain,DataSource,cptype,topologySource
		#
		
		my @lineData = split('\,', $line);
		my ($app, $date, $version, $status, $domain, $ds, $cptype, $topSource) = ($lineData[0], $lineData[1], $lineData[2], $lineData[3], $lineData[4], $lineData[5], $lineData[6], $lineData[7]);
		my $recommended = "";
		
		if (!(defined $domain)) {$domain = "<N/A>";}
		if (!(defined $ds) || (length($ds) == 0)) {$ds = "<N/A>";}
		if (!(defined $cptype)) {$cptype = "<N/A>";}
		if (!(defined $topSource)) {$topSource = "<N/A>";}
		
		#
		# Only interested in installed for now
		#
		
		if ($status =~ /Installation Successful/) {
			#$msg = sprintf("%s, Version: %s (Domain: %s, DataSource: %s, Type: %s, Topology Source: %s)", $app, $version, $domain, $ds, $cptype, $topSource);
			
			if (length($version_data) > 0 ) {
				#
				# We can check this CP version against recommended
				#
				
				my @array = split(chr(10), $version_data);
				my @cpData = grep(/\<OBRCP/, @array);
				
				for my $line(@cpData) {
					
					if ($line =~ /$app/) {
						$recommended = OpsB::Common::GetAttributeFromData($line, "Recommended");
						last;
					}
					
				}
			}
			
			#
			# See if we have a recommended version
			#
			
			if (length($recommended) > 0) {
				
				if (OpsB::Common::MyCompare($version, $recommended) < 0) {
					$sev = M_WARN;
				}
				else {
					$sev = M_OK;
				}

				$msg = sprintf($MSG_CPRecommended, $app, $version, $recommended);
			}
			else {
				$msg = sprintf($MSG_CPNoRecommndation, $app, $version);
				#WO($msg, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
				$sev = M_INFO;
			}
			
			if (length($returnInfo) == 0) {
				$returnInfo = "$msg|$sev";
			}
			else {
				$returnInfo .= "*$msg|$sev";
			}
			
		}
		
	}
	
	#print("==> $data\n");
	WO("End: ProcessContent", M_DEBUG);
	return $returnInfo;
}

#
# Process the BRM file
#

sub ProcessBSMRData() {
	WO("Start: ProcessBSMRData", M_DEBUG);
	
	my $data = shift;
	
	#
	# Just read to the end - the last section information will overwrite all other section information leaving us with the most recent update. Not very efficient, but not
	# a problem in a small file
	#
	
	#printf("$data\n");
	my @allData = split(chr(10), $data);
	my ($package, $version, $state, $patch) = ("", "", "", "");
	my $msg = "";
	
	for my $line(@allData) {
		
		if ($line =~ /package/i) {
			$package = OpsB::Common::ElementFromSplit($line, "=", -1);
		}
		
		if ($line =~ /version/i) {
			$version = OpsB::Common::ElementFromSplit($line, "=", -1);
		}

		if ($line =~ /release.state/i) {
			$state = OpsB::Common::ElementFromSplit($line, "=", -1);
		}

		if ($line =~ /patch.level/i) {
			$patch = OpsB::Common::ElementFromSplit($line, "=", -1);
		}
		
	}
	
	my $sev = M_OK;

	if ((length($package) > 0) & (length($version) > 0) & (length($state) > 0) & (length($patch) > 0)) {
		my $compare = "10.40";
		
		if (OpsB::Common::MyCompare($version, $compare) <0) {
			$sev = M_WARN;
		$msg = sprintf($MSG_BSM_NeedsUpgrade, $package, $version, $patch, $state, $compare);
		}
		else {
			$msg = sprintf($MSG_BSM_NoUpgrade, $package, $version, $patch, $state);
		}
		
		#WO($msg, $sev, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
	}
	
	return $msg, $sev;
	WO("End: ProcessBSMRData", M_DEBUG);
}

#
# Validate the inputs
#

sub CheckInputs() {
	my ($returnValue, $error) = (true, "");

	WO("Start: CheckInputs", M_DEBUG);
	
	if ((length($ARG_ZipFile) > 0) & (!(-e $ARG_ZipFile))) {
		$error = "Zip not found";
		$returnValue = false;
	}
	
	WO("End: GetInputs", M_DEBUG);
	
	return $returnValue;
}
#
# Get inputs
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
	
	$ARG_ZipFile = OpsB::Common::FindArg("input");
	$ARG_Keep = OpsB::Common::FindSwitch("keep");	
	$ARG_Verbose = OpsB::Common::FindSwitch("verbose");
}

#
# Show Help
#

sub ShowHelp() {
	WO("This utility supports several arguments and switches, which can be passed in any order\n");
	WO("OBR checks are made using the utility \"$PMDB_Util\". This is either executed by this script, or can be manually executed to collect the relevant");
	WO("information in a zip file which can then be passed to this script to run in \"offline\" mode. See the information here:");
	WO("");
	WO("\thttps://docs.microfocus.com/itom/Operations_Bridge_Reporter:10.40/Troubleshoot/Troubleshooting_SHR/Capture");
	WO("");
	WO("For instructions on installing, configuring and using the capture tool, including the location of the captured information.");
	
	WO("");
	WO("Inputs:");
	WO("");
	
	WO("  -input <file>\tThe pre-prepared capture zip file created by running the tool manually");
	WO("  -verbose\t\tThe OBR capture tool can return \"success\" even if it fails. This switch will provide additional error information");

	WO("");
	WO("Inputs (Generic):");
	WO("");
	
	OpsB::Common::CommonHelp();
	
	WO("If running \"online\" (no input zip file is provided), then this script must run on the OBR server");
	
	WO("");
}

Main();