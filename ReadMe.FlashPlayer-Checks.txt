Flash Player Checks
===================

Package Release Date:	16 December 2020
Contact:		Andy Doran (andy.doran@microfocus.com), Micro Focus ITOM Customer Success
Publication:		https://marketplace.microfocus.com/itom/content/opsb-version-check-tools - regularly check for a newer revision
Description:		This is a standalone Windows PowerShell script to be used to check Browser Flash Player settings

In case you need more information about the Micro Focus Operations Bridge Evolution program, please contact your Micro Focus Support liaison, or send an email to:

OpsBEvolution@MicroFocus.com


Introduction
============

This PowerShell script is packaged with the OpsBridge Version Check Tool, but is a standalone utility that can be used on any Windows System with PowerShell V2.0 or higher. It will check for installed Browsers (Internet Explorer, Edge, FireFox and Chrome - optionally FireFox Portable). For the supported Browsers it will check to see if Flash Player support is enabled. It will also check for the Windows Update from KB4577586 which disables Flash Player for Microsoft products. This is currently an optional update, but Microsoft will at some point add it to Windows Update Services.

It is advised that Micro Focus products are upgraded to the latest versions for Flash Independence. This utility checks Browser Flash Player support for use with those products not yet upgraded.


Distribution Files
==================

flashplayer-checks.ps1


Usage
=====

This script can be invoked from the command prompt (using the "powershell" prefix) but should be used from PowerShell directly. The script can be invoked with no parameters or switches:

.\flashplayer-checks.ps1

(or "powershell .\flashplayer-checks.ps1" from a command prompt)

Additionally, the following parameters and switches are supported:

-FirefoxPortable <path>		Specify the location of Fire fox Portable (example: -FireFoxPortable G:\).
-CheckAllBrowsers		Switch - if the -FireFoxPortablke parameter is used, no other borowsers are checked unless this switch is specified
-URL <url>			Specify the top-level URL for the site that has the Flash requirements - the Flash WhiteList and AllowList will be checked for this url

Note - the paramater alias FFP can be used in place of the parameter name FirefoxPortable (for example: -FFP G:\).