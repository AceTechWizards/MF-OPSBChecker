OpsBridge Upgrade Version Check Tool - APM (run-apm-check.pl)
=============================================================

Package Release Date:	March 16, 2020
Contact:		Andy Doran (andy.doran@microfocus.com), Micro Focus ITOM Customer Success
Publication:		https://marketplace.microfocus.com/itom/content/opsb-version-check-tools - regularly check for a newer revision
Description:		This tool will provide you with valuable information for your upgrade planning to classic OBM 2020.10. This is the next release of Operations Bridge Manager, 
			providing a Flash Independant User interface that you might be interested in as part of your company's Adobe Flash-Player Removal initiative

In case you need more information about the Micro Focus Operations Bridge Evolution program, please contact your Micro Focus Support liaison, or send an email to:

OpsBEvolution@MicroFocus.com


Introduction
============

The OpsBridge Upgrade Version Check Tool is an evolving set of utilities that are designed to help simply the process of upgrading OpsBridge 
by aiding the identification of installed components and the configuration of the product. 
Where appropriate, issues will be highlighted (such as where a component version is no longer supported).
The current version of the tool is supporting classic OBM/OMi versions 10.12 or higher.

More detailed information is contained in the Micro_Focus_Operations_Bridge_opr-version-check.pdf document which is packaged with the scripts. 
This ReadMe is a "quick start" guide for the APM script.


Basic Concept
=============

The tool consists of several perl scripts that can be executed on either Linux or Windows platforms. 
The APM script can be executed locally on an APM Gateway server (Windows or Linux) or remotely if the JMX security is configured to allow this. See the APM documentation for details. 


Distribution Files
==================

Along with this ReadMe, the perl files are packaged in a zip file that can be extracted on Windows or Linux. 
The directory structure is explained in more detail in the Word document, but it is important when unpacking the zip file that this directory structure is preserved. 
Most of the scripts share some common libraries in perl modules that are referenced through that directory structure.


Running Perl Scripts
====================

Perl is available on both Windows and Linux platforms, but is not usually installed on Windows. 
To run these scripts on Windows, a perl engine such as ActivePerl is required or the Micro Focus Operations Agent provides a perl engine 
which can be used instead (a batch file "oaperl.bat" is provided in this package and this locates the Operations Agent perl engine if it is present). 
On Linux, perl is more commonly installed and available - but if it is not already present, it can be installed (for example using "yum install perl -y").


Running the APM Script
======================

The APM script (run-apm-checks.pl) can be executed locally on an APM Gateway server or remotely. However there are some restrictions in the functions performed. If the Gateway Server is running on Windows, then all tasks will be executed. These are:-

Reading the Database Server details (server, database name and login used)
Reading data from the Database
Reading data from the JMX pages

If the Gateway server is on Linux, then the Database checks cannot be made. Instead the script will display the information (such as host name, database name and login) and the script can then be executed from a Windows platform in order to fetch the information stored in the backend database.

If the script runs remotely from a Windows system, then the Database and JMX data can be retrieved (providing remote JMX has been enabled). In this case, the database host information and JMX server information must be explicitly provided.

If the script runs remotely from a Linux system, then only the JMX data can be retrieved (providing remote JMX has been enabled). In this case, the JMX server information must be explicitly provided.

The inputs for Database processing are:

-dbhost	<host>		The Oracle or SQL Server hosting the APM management database
-db <database>		The database name of the APM management database
-dbuser <login>		The login id with access to the APM database
-dbpwd <password>	The password for the login
-trusted		Switch, used with SQL database server (if specified, the current Windows account is used)
-dbsid <SID>		For Oracle, the SID to use
-dbtype <type>		Either Oracle or "MS SQL" (with MS SQL, the quotes are required). If not specified, MS SQL is assumed

The database processing will only run if the script is executed from a Windows platform. If executed on a Gateway server (Windows) then only the password is required as all other information will be picked up from the APM configuration.

The inputs for JMX processing are:

-host <host>		The server hosting the APM jmx pages
-user <user>		The APM user. If not specified, "admin" is assumed		
-pwd <password>		The password for the APM user
-netrc			Pick credentials from the ._netrc file (requires the ._netiqrc file to exist - see https://community.apigee.com/articles/39911/do-you-use-curl-stop-using-u-please-use-curl-n-and.html)
-nojmx			Do not process any JMX information

If the script is executed from the APM Gateway server then only the user and password is requierd (the user will be assumed to be "admin" if not specified). By default, JMX access is limited to localhost - if this is changed in the infrastructure settings then the script can be executed remotely to retrieve this information. See the APM documentation for more information on enabling JMX remotely.

Example:

	./run-apm-checks.pl -pwd P@ssword

This assumes that the script is running on the Gateway server on Linux and the admin user is being used. Database checks will not be made.

	c:\>perl c:\scripts\run-apm-checks.pl -pwd P@ssword -dbpwd P@ssword2

This assumes that the script is running on the Gateway server on Linux. Database checks will be made.