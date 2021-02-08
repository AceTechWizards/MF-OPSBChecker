OpsBridge Database Toolkit Scripts
==================================

For full instructions on using these scripts, use the documentation in the file dbtools-scripts.pdf.


Installation
============

The scripts are perl scripts that also use java (for database connections). On Windows, an additional support utility is provided. It is important that when unizipping the distribution, the scripts maintain their relationship to thos support files (if you copy the perl scripts to another location, they will no longer work).

The directory structure after unzipping will be

Top level
	db-server-checks.pl
	dbtools-scripts.pdf
	oaperl.bat
	obm-server-checks.pl
	ReadMe.txt (this file)
	run-checks.pl
	settings.dat

	Lib
		java
			mssql-jdbc_auth-8.2.2.x64.dll
			mssql-jdbc_auth-8.2.2.x86.dll
			mssql-jdbc-8.2.2.jre8.jar
			ojdbc6.jar
			opsbdb.jar
			postgresql-42.2.12.jar
		OpsB
			Common.pm
			Database.pm
			HPBSM.pm
		Win	
			mf-utils.exe
			Oracle.managedDataAcess.dll


Usage
=====

Run the checks using the script run-checks.pl as described in the documentation.