OpsBridge Upgrade Version Check Tools - OMi/OBM (opr-version-check)
===================================================================

Package Release Date:	9 December 2020
Contact:		Andy Doran (andy.doran@microfocus.com), Micro Focus ITOM Customer Success
Publication:		https://marketplace.microfocus.com/itom/content/opsb-version-check-tools - regularly check for a newer revision
Description:		This tool will provide you with valuable information for your upgrade planning to classic 2020.10. OBM 2020.05 provides a Flash-independent user interface for 							Operational tasks (such as the event browser). OBM 2020.10 also provides a Flash-independent UI for administration tasks. Running a Flash-independent version of OBM by end of
			calendar year 2020 is very important if your company is following the Adobe Flash-Player removal initiative. Otherwise, please make sure that you can still run Adobe 
			Flash-Player in your browsers beyond end of 2020


In case you need more information about the Micro Focus Operations Bridge Evolution program, please contact your Micro Focus Support liaison, or send an email to:

OpsBEvolution@MicroFocus.com


Introduction
============

The OpsBridge Upgrade Version Check Tool is an evolving set of utilities that are designed to help simply the process of upgrading OpsBridge 
by aiding the identification of installed components and the configuration of the product. 
Where appropriate, issues will be highlighted (such as where a component version is no longer supported).
The current version of the tool is supporting classic OBM/OMi versions 10.12 or higher.

More detailed information is contained in the Micro_Focus_Operations_Bridge_opr-version-check.pdf document which is packaged with the scripts. 
This ReadMe is a "quick start" guide.


Basic Concept
=============

The tool consists of several perl scripts that can be executed on either Linux or Windows platforms. 
They can be executed "online" on the OBM GWS or DPS (meaning they will extract live information from running servers using various tools provided with the product), 
or "offline" (where output from tools such as opr-checker or opr-support-utils can be processed by the scripts). 
These perl scripts can be executed individually, but a "wrapper" script is provided which can be used as the main driver to all of the available scripts.


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

As mentioned, there is a main driver/wrapper script (opr-version-check.pl) that can be used to invoke some or all of the additional scripts. 
How this is used depends on where it is executed and if you decide to run the online of offline mode.


Online Mode
===========

Running in "online" mode will require that the script is executed on the OBM Gateway Server (GWS) or OBM Data Processing Server (DPS). 
The driver script is "opr-version-check.pl". Executing this script without any parameters will trigger to run the Infrastructure checks and Licensing/Support checks. 
This means that the OBM/OMi version and patches are analysed along with some database server information (server name and database server type).
In addition it checks what Licenses and Management Packs (MPs) are installed. 
An example is:-

	/upgrade-tools/opr-version-check.pl -online -pwd P@ssw0rd

or on Windows

	c:\upgrade-tools\oaperl.bat c:\upgrade-tools\opr-version-check.pl  -online -pwd P@ssw0rd

The example above on Windows assumes that no additional perl engine is installed, but that the Operations Agent is present (typically installed on the OBM GWS and DPS) - 
oaperl.bat will locate the perl engine provisioned by the Operations Agent. 
If ActivePerl is installed, then the Windows command would be:

	c:\>perl c:\upgrade-tools\opr-version-check.pl -online -pwd P@ssw0rd

The full list of available parameters is provided in the PDF document.

The switch "-online" can be used, and this will invoke the additional checks for database information (server type - ie. PostgreSQL - and version), 
some configuration information stored in the database, Connected Server information and some OBM user related information. 
However these additional checks will require the proper username/password to be provided.

This aboke example assumes that the username for connecting to OBM/OMi as still the default "admin" user and that the database password matches the OBM user password. 
The username required for the OBM database connection will be retrieved from the configuration information. 
If the passwords are different, then they must be supplied in separate parameters:

	/upgrade-tools/opr-version-check.pl -online -pwd P@ssw0rd1 -db-pwd P@ssw0rd2

See the PDF document or online help (use the switch "-help" to display this) for more details on these parameters, and how to override the default usernames.

NOTE: The database processing utilises Java - of Java is not present then these checks will be skipped (Java is usually installed as part of installing OpsBridge components).

Offline Mode
============

At this time, the Infrastructure check, installed licensing check and installed Management Pack checks can each be performed "offline". 
In order to do this, the information must first be collected and saved in files that can then be used as input for opr-version-check. 

The information for Infrastucture is collected using the tool "opr-checker", which is shipped with OBM and installed on OBM GWS/DPS.
And for the Licensing and Management Pack information the tool "opr-support-utils" is used (also shipped with OBM and installed on OBM GWS/DPS). 
See the PDF document for more details on how to generate these files.

To use offline mode, an example would be:

	/upgrade-tools/opr-version-check.pl -offline -obm-input /tmp/opr-checker.txt -mp-input /tmp/mp.txt


Messages
========

The output from these scripts is prefixed as follows:

[INFO]	Purely informational such as a a progress message ("Fetching information")
[NOTE]	Messages that are not informational, but also not specifically a cause for concern
[OKAY]	A check that "passed" ("There are 4 valid licenses for this system")
[WARN]	A check where some action is recommended ("OBM should be upgraded")
[ERROR]	A check that failed or action is required ("The Management Pack is not supported")
[FATAL]	Some issue has occured which prevents the script from continuing

If colors are enabled, INFO/NOTE messages are in the stanadard console color, OKAY in green, WARN in yellow and ERROR/FATAL in red.


Additional Information
=======================

Visit this page for more information on current OpsBridge content:-

https://docs.microfocus.com/itom/Operations_Bridge:Content/Home

# end of ReadMe
 