#!/usr/bin/perl

# ++
# File:     run-apm-checks.pl
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
#           Andy    Apr-2020	Created
#			Andy	29-Jun-2020	Updated for V2 release
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

use OpsB::Web;
use OpsB::Web qw(ReadWebSiteToString);

use OpsB::Checker;
use OpsB::Database;
use OpsB::HPBSM;

#
# Version of this script
#

our $myVersion = "2020.12";
our $webScriptVersion = OpsB::Web::WEB_VERSION;
our $dbScriptVersion = OpsB::Database::DATABASE_MODULE_VERSION;

#
# Suppoerted inouts
#

our $ARGS_Supported = "user,pwd,host,netrc,dbhost,db,dbpwd,dbport,trusted,dbtype,dbuser,nojmx,dbsid";

#
# Used in this script to "find" other script files
#

our $scriptDir = dirname(abs_path $0);

our $MSG_InvalidArgs = OpsB::Common::MSG_BadArgs;

our $MSG_TopazDBInformation = "Management Database: type %s, server: %s (port %s). Database name: %s, user: %s";
our $MSG_NotLinux = "Currently this script cannot process database information on the linux platform. Re-run on Windows, specifying the database information shown";
our $MSG_NoDatabase = "No database name was supplied"; 
our $MSG_FailedURL = "Unable to access url on host %s. Make sure the JMX password (or ._netrc file) is supplied. Error: %s";
our $MSG_UnexpectedURLResponse = "The data returned is inconsistent with %s. There may be errors included in the results:\n%s";
our $MSG_DBError = "Failed to get the database version. Error: %s";
our $MSG_ComponentVersionFailed = "Failed to get the %s information. Error: %s";
our $MSG_DBServerInformation_Ora = "%s server %s (port %s, SID %s) - Database: %s accessed with user: %s";
our $MSG_DBServerInformation = "%s server %s (port %s) - Database: %s accessed with user: %s";
our $MSG_DBServerInformationBPM_Ora = "BPM Host %s\n\t  Server type: %s server %s (port %s, SID %s), Database: %s, user: %s";
our $MSG_DBServerInformationBPM = "BMP Host %s\n\t  Server type: %s, Host: %s (port %s), Database: %s, user: %s";
our $MSG_HostsInformation = "Server: %s (%s), version: %s";
our $MSG_ServerVersionOK = "Server: %s (%s) version %s. Roles:\n\t%s";
our $MSG_ServerVersionNotOK = "Server: %s (%s) version %s. Expected version 9.5 or higher. Roles:\n\t%s";
our $MSG_LicenseInformation = "%s license %s, valid: %s (capacity: %s, days remaining: %s)";
our $MSG_NoLicenses = "No licenses found";
our $MSG_NoValidLicenses = "There are no valid licenses on this system";
our $MSG_NoValidPermanentLicenses = "There are no valid permanent licenses, %s valid evaluation licenses";
our $MSG_PermAndEvalLicenses = "There are %s valid licenses on this system, with %s evaluation licenses";
our $MSG_ServerTypeAndVersion = "Database server: %s (%s), version: %s";

#our $Q_APM_Sessions_Ora = "select SESSION_NAME, SESSION_DBTYPE, SESSION_DB_NAME, SESSION_DB_HOST, SESSION_DB_PORT, SESSION_DB_SID, SESSION_DB_UID from 0.SESSIONS";
#our $Q_APM_EUMBPM_Hosts_Ora = "select HOST_NAME, HOST_KEY, VERSION, HOST_UI_URL from 0.EUMBPM_HOSTS"
#
# Input arguments
#

our $ARG_Host = "";
our $ARG_Port = "";
our $ARG_User = "admin";
our $ARG_PWD = "";
our $ARG_UseSecure = true;

our $ARG_DBPwd = "";
our $ARG_DBTrusted = false;
our $ARG_DBHost = "";
our $ARG_DB = "";
our $ARG_DBPort = "";
our $ARG_DBType = "";
our $ARG_DBSID = "";
our $ARG_DBUser = "";

our $ARG_NoJMX = false;

our $BSM_Home = OpsB::HPBSM::TopazDir();

#
# Url info
#

our $JMX_Base = "http://%s:%s/invoke?operation=%s";
our $JMX_ServerDeployment = "displayDeploymentReport&objectname=BSM-Platform%3Aservice%3DBSMServerDeployment"; #"invoke?operation=displayDeploymentReport&objectname=BSM-Platform%3Aservice%3DBSMServerDeployment";
our $JMX_ConfigurationValidator = "ConfigurationValidatorReport&objectname=BSM-Platform%3Aservice%3DBSMConfigurationValidator";
our $JMX_LicenseInfo = "displayAllLicenseInformation&objectname=BSM-Platform%3Aservice%3DLicenseManager&value0=1&type0=int";

#
# Start here
#

sub Main() {
	#
	# Check the support utility exists first!
	#
		
	if (!(-e $MF_UTIL)) {
		WO("The support utility is missing", M_FATAL);
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

	my $otherModules = sprintf("HPBBSM Version: %s, Database Version: %s, Web Version: %s", OpsB::HPBSM::HP_BSM_MODULE_VERSION, $dbScriptVersion, $webScriptVersion);
    my $useLog = OpsB::Common::SayHello($myVersion, $otherModules, "Utility to check APM information");

    if ($ARG_Help == true) {
        ShowHelp();
        return;
    }

	#
	# Show the inputs
	#
	
	#my $inputs = "inputs:\n  user:\t$ARG_User\n  host:\t$ARG_Host\n  netrc:\t$ARG_UseSecure\n  dbhost:\t$ARG_DBHost\n  db:\t\t$ARG_DB\n  dbport:\t$ARG_DBPort\n  dbtype:\t$ARG_DBType\n  dbuser:\t$ARG_DBUser\n  nojmx:\t$ARG_NoJMX\n  dbsid:\t$ARG_DBSID";
	#WO($inputs, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Verbose);
	
    #
    # Validate the inputs, quit if bad
    #

	my ($ok, $error) = CheckInputs();
	
    if ($ok == false) {
		ShowHelp();
		WO($error, M_ERROR);
        return;
    }

    #
    # Check we got no invalid inputs
    #
    
    my ($argsOK, $badList) = OpsB::Common::ValidateArgs($ARGS_Supported);

    if ($argsOK == false) {
        my $msg = sprintf($MSG_InvalidArgs, $badList);
        ShowHelp();
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
	#
	# First do database stuff if we have the information
	#
	
	my $msg = "";
	my ($host, $port, $db, $user, $type, $sid) = ("", "", "", "", "", "");
	
	WO("Start: ProcessData", M_DEBUG);
	
	if ((length($BSM_Home) > 0) && (!($BSM_Home =~ /%/))) {
		#
		# Use Checker to read Database information from Tpaz by passing dummy information to the call which forces it
		# to look for TopazInfra.ini
		#
		
		my %DBInfo = OpsB::Checker::GetMgmtDBInfo("dummy", false);
		
		if (defined $DBInfo{"Host"}) {
			$host = $DBInfo{"Host"};
			$port = $DBInfo{"Port"};
			$db = $DBInfo{"Database"};
			$user = $DBInfo{"User"};
			$type = $DBInfo{"DBType"};
			if (defined $DBInfo{"SID"}) {$sid = $DBInfo{"SID"};}
		}
		
	}
	else {
		#
		# If we are on Windows then we can allow the input DB information to be used instead of reading form the TopazInfra.ini file
		#
		
		$host = $ARG_DBHost;
		$port = $ARG_DBPort;
		$db = $ARG_DB;
		$user = $ARG_DBUser;
		$type = $ARG_DBType;
		$sid = $ARG_DBSID;
	}
	
	ProcessDBData($host, $db, $port, $user, $sid, $type);

	if ($ARG_NoJMX == true) {
		#
		# Chose not to process the URL stuff
		#
		
		return;
	}
	
	my $url = sprintf($JMX_Base, $ARG_Host, $ARG_Port, $JMX_ServerDeployment);
	my %deployment = (
		url => $url, 
		user => $ARG_User, 
		password => $ARG_PWD, 
		credentials => $ARG_UseSecure
	);
	
	my ($deploymentOK, $SRVDeployment, $deploymentError) = ReadWebSiteToString(%deployment);

	if (($deploymentOK == false) || (length($SRVDeployment) == 0)) {
		$msg = sprintf($MSG_FailedURL, $ARG_Host, $deploymentError);
		WO($msg, M_FATAL);
		return;
	}
		
	if ($SRVDeployment =~ /BSMServerDeployment/i) {
		WO("");
		GetServerDeployment($SRVDeployment);
	}
	else {
		#print("==>$SRVDeployment\n");
		my $plain = OpsB::Web::MakeHTMLPlain($SRVDeployment);
		$msg = sprintf($MSG_UnexpectedURLResponse, "BSM Server Deployment Server", $plain);
		WO($msg, M_WARN);
		return;
	}
	
	#
	# If we got the first, try the rest
	#
	
	$url = sprintf($JMX_Base, $ARG_Host, $ARG_Port, $JMX_ConfigurationValidator);
	my %configuration = (
		url => $url,
		user => $ARG_User,
		password => $ARG_PWD,
		credentials => $ARG_UseSecure
	);
	
	my ($configOK, $Config, $configError) = ReadWebSiteToString(%configuration);
	
	if (($configOK == false) || (length($Config) == 0)) {
		$msg = sprintf($MSG_FailedURL, $ARG_Host, $configError);
		WO($msg, M_FATAL);
		return;
	}
	
	if ($Config =~ /BSMConfigurationValidator/i) {
		WO("");
		GetConfig($Config);
	}
	
	$url = sprintf($JMX_Base, $ARG_Host, $ARG_Port, $JMX_LicenseInfo);
	my %license = (
		url => $url,
		user => $ARG_User,
		password => $ARG_PWD,
		credentials => $ARG_UseSecure
	);
	
	my ($licOK, $License, $licError) = ReadWebSiteToString(%license);
	
	if (($licOK == false) || (length($License) == 0)) {
		$msg = sprintf($MSG_FailedURL, $ARG_Host, $licError);
		WO($msg, M_FATAL);
		return;
	}
	
	if ($License =~ /LicenseManager/i) {
		WO("");
		GetLicenses($License);
	}

	WO("End: ProcessData", M_DEBUG);
}

#
# Get the information from the database(s) directly
#

sub ProcessDBData() {
	my ($dbHost, $dbName, $dbPort, $dbUser, $dbSID, $dbType) = @_;
	my ($msg, $ok, $data, $error) = ("", false, "", "");
	
	WO("Start: ProcessDBData", M_DEBUG);
	
	WO("Database information...", M_INFO);
	
    $data = OpsB::Database::GetServerVersion($dbHost, $dbPort, $dbUser, $ARG_DBPwd, $dbName, $dbType, $dbSID);
	
    if (length($data) == 0) {
		#$msg = sprintf($MSG_DBError, $error); #sprintf($MSG_ERR_ServerVerion, $error);
        #WO($msg, M_ERROR, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
		return;
    }

	$msg = sprintf($MSG_ServerTypeAndVersion, $dbHost, $dbType, $data);
	WO($msg, M_INFO);
	
	#
	# Get the version information now
	#
	
    $data = OpsB::Database::APMGenericQuery(OpsB::Database::APM_Version_Query, $dbHost, $dbPort, $dbUser, $ARG_DBPwd, $dbName, $dbType, $dbSID);
		
	if (length($data) > 0) {
		WO("");
		WO("Server configuration...", M_INFO);
		DisplayServerVersionInformation($data);
	}
	
	#
	# Now Database Analytics
	#

    $data = OpsB::Database::APMGenericQuery(OpsB::Database::APM_Analytics_Query, $dbHost, $dbPort, $dbUser, $ARG_DBPwd, $dbName, $dbType, $dbSID);

	if (length($data) > 0) {
		WO("");
		WO("Analytics Databases...", M_INFO);
		
		#
		# Loop through 
		#
		
		my @array = split(chr(10), $data);
		
		for my $line(@array) {
			my @detail = split(",", $line);
			my ($dbTypeRaw, $dbHost, $dbPort, $dbName, $dbUser, $dbSID) = ($detail[0], $detail[1], $detail[2], $detail[3], $detail[4], $detail[5]);
			if (!(defined $dbSID)) {$dbSID = "";}

			$msg = sprintf($MSG_DBServerInformation_Ora, OpsB::Database::DBTYPE_Oracle_String, $dbHost, $dbPort, $dbSID, $dbName, $dbUser);
			if ($dbTypeRaw == 200) {$msg = sprintf($MSG_DBServerInformation, OpsB::Database::DBTYPE_MSSQL_String, $dbHost, $dbPort, $dbName, $dbUser);}

			WO($msg, M_INFO);
		}
		
		#DisplayServerVersionInformation($data);
	}	

	#
	# Now Sessions
	#

    $data = OpsB::Database::APMGenericQuery(OpsB::Database::APM_Sessions_Query, $dbHost, $dbPort, $dbUser, $ARG_DBPwd, $dbName, $dbType, $dbSID);
	
	if (length($data) > 0) {
		WO("");
		WO("BPM Sessions information...", M_INFO);

		#
		# Loop through 
		#
		
		my @array = split(chr(10), $data);
		
		for my $line(@array) {
			my @detail = split(",", $line);
			my ($name, $dbTypeRaw, $dbName, $dbHost, $dbPort, $dbSID, $dbUser) = ($detail[0], $detail[1], $detail[2], $detail[3], $detail[4], $detail[5], $detail[6]);
			if (!(defined $dbSID)) {$dbSID = "";}

			$msg = sprintf($MSG_DBServerInformationBPM_Ora, $name, OpsB::Database::DBTYPE_Oracle_String, $dbHost, $dbPort, $dbSID, $dbName, $dbUser);
			if ($dbTypeRaw == 2) {$msg = sprintf($MSG_DBServerInformationBPM, $name, OpsB::Database::DBTYPE_MSSQL_String, $dbHost, $dbPort, $dbName, $dbUser);}

			WO($msg, M_INFO);
		}
	}	
	
	#
	# Now Hosts
	#

    $data = OpsB::Database::APMGenericQuery(OpsB::Database::APM_BPMHosts_Query, $dbHost, $dbPort, $dbUser, $ARG_DBPwd, $dbName, $dbType, $dbSID);
    #($ok, $data, $error) = OpsB::DB::APMGenericQuery($dbType, $dbHost, $dbPort, $dbName, $dbUser, $ARG_DBPwd, "SID", $dbSID, $ARG_Timeout, OpsB::DB::APM_BPMHosts_Query);
	
	if (length($data) > 0) {
		WO("");
		WO("Hosts information...", M_INFO);
		#
		# Loop through 
		#
		
		my @array = split(chr(10), $data);
		
		for my $line(@array) {
			my @detail = split(",", $line);
			my ($Host, $IP, $url) = ($detail[0], $detail[1], $detail[2]);
			$msg = sprintf($MSG_HostsInformation, $Host, $IP, $url);

			WO($msg, M_INFO);
		}
	}	

	WO("End: ProcessDBData", M_DEBUG);
}

#
# Display the server and version information for each server we found
#

sub DisplayServerVersionInformation() {
	my $data = shift;
	
	WO("Start: DisplayServerVersionInformation", M_DEBUG);

	#
	# The data is lf then csv
	#
	
	my @array = split(chr(10), $data);
	my ($roles, $lastIP, $msg, $sev) = ("", "!", "", M_OK);
	my ($server, $ip, $type, $version) = ("", "", "", "");
	
	for my $line(@array) {
		my @detail = split(",", $line);
		($server, $ip, $type, $version) = ($detail[0], $detail[1], $detail[2], $detail[3]);
		
		#
		# One server may have many roles - AND different server names
		#
		
		if ($lastIP ne $ip) {
			#
			# If this is the first server then just add the new information. Otherwise show the last server detail
			#
			
			if ($lastIP ne "!") {
				#
				# Show the last server
				#
				
				if (OpsB::Common::MyCompare($version, "9.5") > -1) { # ???? What are we looking for??
					$sev = M_OK;
					$msg = sprintf($MSG_ServerVersionOK, $server, $ip, $version, $roles);
				}
				else {
					$sev = M_WARN;
					$msg = sprintf($MSG_ServerVersionNotOK, $server, $ip, $version, $roles);
				}
				
				WO($msg, $sev);
			}

			$roles = $type;
		}
		else {		
			$roles .="; $type";
		}
		
		$lastIP = $ip;
	}

	if ($lastIP ne "!") {
		#
		# Show the very last server
		#
		
		if (OpsB::Common::MyCompare($version, "9.5") > -1) { # ??? What are we looking for??
			$sev = M_OK;
			$msg = sprintf($MSG_ServerVersionOK, $server, $ip, $version, $roles);
		}
		else {
			$sev = M_WARN;
			$msg = sprintf($MSG_ServerVersionNotOK, $server, $ip, $version, $roles);
		}
		
		WO($msg, $sev);
	}
	
	WO("End: DisplayServerVersionInformation", M_DEBUG);
}

#
# Process Licenses
#

sub GetLicenses() {
	my $agentData = shift;
	
	WO("Start: GetLicenses", M_DEBUG);

	#
	# The data we need is in the "status" table"
	#
	
	my $posTable = index($agentData, "table id=\"status\"");
	
	if ($posTable == -1) {
		return;
	}
	
	my $posEndTable = index($agentData, "\<\/table", $posTable);
	
	if ($posEndTable < $posTable) {
		return;
	}
	
	WO("Licensing information...", M_INFO);
		
	my $chunk = substr($agentData, $posTable, ($posEndTable - $posTable));
	my @array = split("\<tr\>", $chunk);
	
	#
	# tr is row - and ignore the header#
	#
	
	my ($totalLicenses, $totalEval, $validPerm, $validEval, $isEval, $isValid, $sev) = (0, 0, 0, 0, true, true, M_OK);

	my ($licName, $licType, $licValid, $licCapacity, $licDaysLeft,) = ("", "", "", "", "");
	
	for my $row(@array) {

		if ($row =~ /^\<td\>/) {
			#
			# Each row contains data in columns defined by <td></td>
			#
			
			my @tdArray = split("\<\/td\>", $row);
			
			foreach my $col(@tdArray) {
				$licName = CleanString($tdArray[0]);
				$licType = CleanString($tdArray[2]);
				$licValid = CleanString($tdArray[3]);
				$licCapacity = CleanString($tdArray[4]);
				$licDaysLeft = CleanString($tdArray[5]);
				
			}

			my $capacityString = $licCapacity;
			if ($licCapacity == 2147483647) {$capacityString = "unlimited";}

			my $remainingString = $licDaysLeft;
			if ($licDaysLeft == 2147483647) {$remainingString = "unlimited";}

			if ($licType =~ /EVALUATION/i) {
				$isEval = true;
			}
			else {
				$isEval = false;
			}
			
			if ($licValid =~ /true/i) {
				$isValid = true;
			}
			else {
				$isValid = false;
			}
			
			$totalLicenses +=1;
			
			if ($isValid == true) {
				$sev = M_OK;

				if ($isEval == true) {
					$validEval +=1;
				}
				else {
					$validPerm +=1;
				}
				
			}
			else {
				$sev = M_WARN;
			}
			
			#
			# Only print details of permanent licenses
			#
			
			if ($isEval == false) {
				my $msg = sprintf($MSG_LicenseInformation, $licType, $licName, $licValid, $capacityString, $remainingString);
				WO($msg, $sev);
			}

		}
		
	}
	
	if ($totalLicenses == 0) {
		WO($MSG_NoLicenses, M_WARN);
	}
	else {
		
		if ($validPerm == 0) {
		
			if ($validEval == 0) {
				WO($MSG_NoValidLicenses, M_WARN);
			}
			else {
				my $msg = sprintf($MSG_NoValidPermanentLicenses, $validEval);
				WO($msg, M_WARN);
			}
			
		}
		else {
			my $msg = sprintf($MSG_PermAndEvalLicenses, $validPerm, $validEval);
			WO($msg, M_OK);
		}
		
	}
	
	WO("End: GetLicenses", M_DEBUG);
}

sub CleanString() {
	my $string = shift;
	$string =~ s/(<.[^(><.)]+>)//g;
	return $string;
}

#
# Process output for server deployment
#

sub GetServerDeployment() {
	my $agentData = shift;

	WO("Start: GetServerDeployment", M_DEBUG);
	
	my @array = split(chr(10), $agentData);
	my ($inRequired, $inActual, $inAlign) = (false, false, false);
	
	WO("BSM Server Deployment information...", M_INFO);
	
	for my $line(@array) {
		
		if (!($line =~/^</)) {
			
			if (length($line) == 0) {($inRequired, $inActual, $inAlign) = (false, false, false);}
			
			if ($inRequired || $inActual || $inAlign) {
			
				if (!($line =~ /====/)) {
					my $sev = M_INFO;
					
					if ($inAlign == true) {
					
						if ($line =~ /is aligned/i) {
							$sev = M_OK;
						}
						else {
							$sev = M_WARN;
						}
						
					}
					
					WO($line, $sev);
				}
				
			}

			#if ($line =~ /Required HW profile/i) {$inRequired = $true;}
			if ($line =~ /Actual HW Profiles/i) {$inActual = true;}
			if ($line =~ /Machines alignment/i) {$inAlign = true;}
			
		}
		
	}
	
	WO("End: GetServerDeployment", M_DEBUG);
}

#
# Process output for server deploymen
#

sub GetConfig() {
	my $agentData = shift;

	WO("Start: GetConfig", M_DEBUG);
		
	WO("BSM Configuration information...", M_INFO);
	
	#
	# The data we need is not in Lf separated lines, but in a chunk of data. So we have to lkook for the data based on the headings for <h2>
	#
	
	my @array = split("\<h2\>", $agentData);
	
	foreach my $chunk(@array) {
		#
		# The header is our section title, so find the end if that
		#
		
		my $posEndHeader = index($chunk, "\<\/h2\>");
		
		if ($posEndHeader > -1) {
			#
			# This gives us a header
			#
			
			my $sectionTitle = substr($chunk, 0, $posEndHeader);
			
			#
			# If there is anythiung between the end header tag and a break or paragraph, then pick that up
			#
			
			my $posPara = index($chunk, "\<p", $posEndHeader);
			my $posBreak = index($chunk, "\<br\>", $posEndHeader);
			my $posLine = index($chunk, "\<li\>", $posEndHeader);
			
			#
			# Find the smallest non negative number
			#
			
			my $posTest = $posEndHeader + 5; # for the characters in </h2>
			my $posLowest = $posTest;
			if ($posPara > $posTest) {$posLowest = $posPara;}
			if (($posBreak > $posTest) && ($posBreak < $posLowest)) {$posLowest = $posBreak;}
			if (($posLine > $posTest) && ($posLine < $posLowest)) {$posLowest = $posLine;}
			
			#print("End: $posEndHeader, Test: $posTest, Para: $posPara, Break: $posBreak, Line: $posLine, Lowest: $posLowest\n");
			
			#
			# Now we know the "lowest" position - break, paragraph or line. See if that is more than one character higher than the header end, if so use that text
			#
			
			my $header = sprintf("%s", $sectionTitle);

			if ($posLowest > ($posTest + 1)) {
				#
				# Get the information between the 2 points
				#
				
				my $lineInformation = substr($chunk, $posTest, ($posLowest - $posTest));
				$header = sprintf("%s (%s)", $sectionTitle, $lineInformation)
			}
			
			#WO($msg, $M_INFO, $ARG_Color, $ARG_Debug, $ARG_Log, $ARG_Quiet);
			
			#
			# Now just look for "validation" and see of this passed ot not
			#
			
			my $posValidation = index($chunk, "\>Validation");
			
			if ($posValidation > -1) {
				#
				# Find the end of the sentence
				#
				
				$posValidation +=1;
				my $posEndValidation = index($chunk, "\<\/", $posValidation);
				
				if ($posEndValidation > $posValidation) {
					my $validationInfo = substr($chunk, $posValidation, ($posEndValidation - $posValidation));
					my $sev = M_WARN;
					
					if ($validationInfo =~ /PASSED/i) {$sev = M_OK;}
					my $msg = sprintf("%s - %s", $header, $validationInfo);
					WO($msg, $sev);
				}
				
			} # Check for validation sentence
			
		} # found header
		
	} # Loop
	
	WO("End: GetConfig", M_DEBUG);
}

#
# Validate the inputs
#

sub CheckInputs() {
	my ($error, $returnValue) = ("", true);

	WO("Start: CheckInputs", M_DEBUG);
	
	if (length($ARG_Host) == 0) {
		#
		# Assume localhost
		#
		
		$ARG_Host = "localhost";
	}
	
	if ((length($ARG_User) == 0) && (length($ARG_PWD) > 0)) {
		#
		# Default to the admin account if a password is supplied, but allow no user as "secure" might be used or they might be no authentication
		#
		
		$ARG_User = "admin";
	}
	
	if ((length($ARG_PWD) == 0) && ($ARG_UseSecure == false) && (length($ARG_User) > 0)) {
		$error = "The password cannot be blank unless secure authentication is being used";
		$returnValue = false;
	}
	
	if ($ARG_UseSecure == true) {
		#
		# Assume that the credentials file will be used, so set user/password to nothing.
		#
		
		$ARG_User = "";
		$ARG_PWD = "";
	}
	
	WO("End: GetInputs", M_DEBUG);
	
	return $returnValue, $error;
}
#
# Get inputs
#

sub GetInputs() {
	
	$ARG_Debug = OpsB::Common::FindSwitch("debug");
	$ARG_Color = OpsB::Common::FindSwitch("nocolor");
	$ARG_Log = OpsB::Common::FindSwitch("log");
	$ARG_Quiet = OpsB::Common::FindSwitch("quiet");
	$ARG_NoWelcome = OpsB::Common::FindSwitch("nowelcome");
	$ARG_Quiet = OpsB::Common::FindSwitch("quiet");
	$ARG_Help = OpsB::Common::FindSwitch("help") || OpsB::Common::FindSwitch("h") || OpsB::Common::FindSwitch("\?");
	$ARG_Timeout = OpsB::Common::Timeout(OpsB::Common::FindArg("timeout"));
	
	#
	# Switch around the color settings - found value for "nocolor" so if that is true, set "ARG_Color" to false;
	#
	
	if ($ARG_Color == true) {$ARG_Color = false;} else {$ARG_Color = true;}	
	
	$ARG_Host = OpsB::Common::FindArg("host");
	$ARG_Port = OpsB::Common::GetNumericFromString(OpsB::Common::FindArg("port"), 1024, 99999, 29000);
	$ARG_User = OpsB::Common::FindArg("user");
	$ARG_PWD = OpsB::Common::FindArg("pwd");
	$ARG_UseSecure = OpsB::Common::FindSwitch("secure");
	
	$ARG_DBPwd = OpsB::Common::FindArg("dbpwd");
	$ARG_DBTrusted = OpsB::Common::FindSwitch("trusted");
	$ARG_DBHost = OpsB::Common::FindArg("dbhost");
	$ARG_DB = OpsB::Common::FindArg("db");
	$ARG_DBPort = OpsB::Common::FindArg("dbport");
	$ARG_DBType = OpsB::Common::FindArg("dbtype");
	$ARG_DBSID = OpsB::Common::FindArg("dbsid");
	$ARG_DBUser = OpsB::Common::FindArg("dbuser");
	
	$ARG_NoJMX = OpsB::Common::FindSwitch("nojmx");
	
	$ARG_Help = OpsB::Common::FindSwitch("help") || OpsB::Common::FindSwitch("h");

	#
	# Database server settings to allow for running on a server remote to APM if you have the databse details and JMX is enabled remotely
	#
	
	if (($ARG_DBTrusted == true) && (length($ARG_DBPwd) == 0)) {
		#
		# Assume APM UI password can be used for the Database logon
		#
		
		$ARG_DBPwd = $ARG_PWD;
	}
	
	if (length($ARG_DBHost) > 0) {
		#
		# The databse override information is being specified so we can run remotely
		#
		
		if ((lc $ARG_DBType ne lc OpsB::Database::DBTYPE_MSSQL_String) && (lc $ARG_DBType ne lc OpsB::Database::DBTYPE_Oracle_String)) {
			#
			# Only SQL and Oracle can be used for APM
			#
			
			$ARG_DBType = OpsB::Database::DBTYPE_MSSQL_String;
		}
		
		#
		# Set the port to be in range - ie numeric
		#
		
		if ($ARG_DBType eq OpsB::Database::DBTYPE_MSSQL_String) {
			#
			# Default SQL port is 1433
			#
			$ARG_DBPort = OpsB::Common::GetNumericFromString($ARG_DBPort, 1024, 99999, 1433);
		}
		else {
			#
			# Default Oracle port is 1521
			#

			$ARG_DBPort = OpsB::Common::GetNumericFromString($ARG_DBPort, 1024, 99999, 1521);
		}
		
	}
}

#
# Show Help
#

sub ShowHelp() {
	WO("This utility supports several arguments and switches, which can be passed in any order\n");
	WO("APM checks are made using a combination of \"JMX\" and direct database connections. The script can run locally on an APM Gateway server, or");
	WO("remotely. For the script to run remotely and be allowed to retrieve the information from the JMX pages, remote access must be enabled. If that");
	WO("is not enabled then this information may only be obtained by running the script locally on the Gateway server.");
	WO("\nTo enable access to JMX remotely, see the documentation for changing the infrastructure settings.\n");
	
	WO("The information that is obtained from the database requires this script to be executed from a Windows system, regardless of whether the database");
	WO("server is Oracle or MS SQL. If the database information (type, host, credentials and database name) are known then these details can be provided");
	WO("using the input arguments listed below. If they are not known, the information can be obtained by running this script first on the Gateway server.");
	WO("\nIf APM is installed on a Windows platform, then running the script on the Gateway server will allow all information to be gathered at one time.");
	
	WO("");
	WO("Inputs (JMX):");
	WO("");
	
	#our $ARGS_Supported = "user,pwd,host,netrc,dbhost,db,dbpwd,dbport,trusted,dbtype,dbuser,nojmx,dbsid";
	WO("  -host <host>\t\tHost name of the Gateway server if running remotely");
	WO("  -user <user>\t\tUser with access rights to the JMX pages (if not provided, \"admin\" is used)");
	WO("  -pwd <pass>\t\tThe password for the JMX user");
	WO("  -netrc\t\tIf this switch is specified then the script will look for the file ~/._netrc (or _netrc in the home directory on Windows) for credentials");
	WO("  -nojmx\t\tIf this switch is speficied then no jmx processing will take place");
	
	WO("");
	WO("Inputs (Database):");
	WO("");
	
	WO("  -dbhost <host>\tThe host name of the database server");
	WO("  -db <database>\tThe Management database name");
	WO("  -dbuser <user>\tThe user id for the databse server connection");
	WO("  -dbpwd <pass>\t\tThe password for the database user id");
	WO("  -dbport <port>\tThe port used to connect to the database server");
	WO("  -trusted\t\tThe switch only applies with a SQL Database - if specifed, the current Windows user is used to connect");
	WO("  -dbsid <SID>\t\tFor an Oracle server, this specifies the SID for the database connection");
	WO("  -dbtype <type>\tThe type of database server - either \"Oracle\" or \"MS SQL\" (use quotes when specifying \"MS SQL\"");
	
	WO("");
	WO("Inputs (Generic):");
	WO("");
	
	OpsB::Common::ShowCommonHelp();
	
	WO("If running this script on the APM Gateway servers on a Windows platform, then only the database user password is required for the database inputs. All");
	WO("other information will be retrieved from the configuration detected by the script. An example of running on Windows:\n");
	WO("  c:\\>perl c:\\opr-version-check\\run-apm-checks.pl -pwd P\@ssw0rd1 -dbpwd P\@ssw0rd2\n");
	WO("This will process both the JMX information on the local server, and connect to the database (Oracle or MS SQL) to gather information stored there.");
	WO("\nThe script supports the use of a \"._netrc\" file for connecting to the JMX pages. This allows for the user/password to be stored in a file rather");
	WO("than passed as an input parameter. This file should be located in the home directory (~/ on Linux or \%USERPROFILE\% on Windows). For more");
	WO("information on how to use this file, see:");
	WO("\n https://docs.oracle.com/cd/E19455-01/806-0633/6j9vn6q5f/index.html \n");
	WO("NOTE: This script expects the \"machine\", \"login\" and \"password\" information on separate lines if using this method.");
	
	WO("");
}

Main();