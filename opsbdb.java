//
// Imports
//

import java.sql.*;
import java.io.File;
import java.io.FileNotFoundException;
import java.util.Scanner;

public class opsbdb{
	//
	// Some Globals used for inputs
	//
	
	private static String server = "";
	private static String port = "";
	private static String db = "";
	private static String user = "";
	private static String pwd = "";
	private static String sid = "";
	private static String dbtype = "";
	private static String dbtypeString = "";
	private static String query = "";
	private static boolean headers = false;
	private static String queryFile = "";
	private static boolean help = false;
	private static boolean debug = false;
	private static String sep = "";
	private static boolean ignorePort = false;
	private static boolean allowUpdates = false;
	
	private static final String DBTYPE_SQL = "1";
	private static final String DBTYPE_Oracle = "2";
	private static final String DBTYPE_PG = "3";
	private static final String DBTYPE_SQL_String = "MS SQL";
	private static final String DBTYPE_Oracle_String = "Oracle";
	private static final String DBTYPE_PG_String = "Postgresql";
	
	private static final int MIN_DBTYPE = 1;
	private static final int MAX_DBTYPE = 3;
	private static final int DEFAULT_DBTYPE = 1;
	
	private static final int MIN_PORT = 0;
	private static final int MAX_PORT = 32767;
	private static final int DEFAULT_SQL_Port = 1433;
	private static final int DEFAULT_Oracle_Port = 1521;
	private static final int DEFAULT_PG_Port = 5432;
	
	private static final String DEFAULT_SID = "ora";
	
	private static final String DEFAULT_Sep = ",";
	
	private static boolean isUpdateCommand = false;
	
	//
	// Exit codes
	//
	
	private static final int EXIT_OK = 0;
	private static final int EXIT_BAD = 1;
	private static final int EXIT_UNSUPPORTED_DBTYPE = 2;
	private static final int EXIT_BAD_CLASS = 3;
	private static final int EXIT_CONNECT_FAILED = 4;
	private static final int EXIT_SQL_FAIL = 5;
	
	private static int ExitCode = EXIT_OK;

	//
	// Entry point
	//
	
	public static void main(String[] args) {
		boolean ok = GetAndCheckInputs(args);
		DB(String.format("Server:\t%s\n\tPort:\t%s\n\tDB:\t%s\n\tUser:\t%s\n\tType:\t%s\n", server, port, db, user, dbtypeString));
		
		ExitCode = EXIT_OK;
		
		if ((ok) && (!help)) {
			ProcessData();
		}
		else {
			
			if (!ok) {
				ExitCode = EXIT_BAD;
			}
			else {
				ShowHelp();
			}
		}
		
		System.exit(ExitCode);
	}
	
	//
	// Main processing
	//
	
	private static void ProcessData() {		
		DB(String.format("Connecting to %s server %s (port: %s), database: %s ...", dbtypeString, server, port, db));
		
		String URL = "";
		String CNXClass = "";
		
		//
		// Set the URL and Class to use based on the database type
		//
		
		switch (dbtype) {
			case DBTYPE_SQL:
				String iSec = "true";
				if (user.length() > 0) {iSec = "false";}

				if ((server.indexOf('\\') > -1) || (ignorePort)){
					URL = String.format("jdbc:sqlserver://%s;databasename=%s;integratedSecurity=%s", server, db, iSec);
				}
				else {
					URL = String.format("jdbc:sqlserver://%s:%s;databasename=%s;integratedSecurity=%s", server, port, db, iSec);
				}
				
				CNXClass = "com.microsoft.sqlserver.jdbc.SQLServerDriver";
				break;
				
			case DBTYPE_Oracle:
				URL = String.format("jdbc:oracle:thin:@%s:%s:%s", server, port, sid);
				CNXClass = "oracle.jdbc.OracleDriver";
				break;
				
			case DBTYPE_PG:
				URL = String.format("jdbc:postgresql://%s:%s/%s", server, port, db);
				CNXClass = "dummy";
		}
		
		if (CNXClass.length() == 0) {
			WO(String.format("The database type %s (%s) is not currently supported", dbtype, dbtypeString));
			ExitCode = EXIT_UNSUPPORTED_DBTYPE;
			return;
		}
		
		DB(String.format("Class: %s, cnx: %s", CNXClass, URL));
		
		Connection conn = null;
		
		try {
			
			if (!(dbtype.equals(DBTYPE_PG))){
				Class.forName(CNXClass);
			}
			
			conn = DriverManager.getConnection(URL, user, pwd);
		}
		catch (ClassNotFoundException e) {
			WO(String.format("**** Database Connection Class Error with class: %s\n%s", CNXClass, e.getMessage()));
			ExitCode = EXIT_BAD_CLASS;
			//e.printStackTrace();
		}
		catch (SQLException e) {
			WO(String.format("**** Database Connection Error with URL: %s\n%s", URL, e.getMessage()));
			ExitCode = EXIT_CONNECT_FAILED;
			//e.printStackTrace();  //e.getMessage;
		}
		finally {
		
			try {
				
				if(conn != null && !conn.isClosed()) {
					DB("Connected...");
					
					RunQuery(conn, query);
					conn.close();
				}
			}
		catch (SQLException e) {
			WO(String.format("**** Error processing in SQL:\n%s", e.getMessage()));
			ExitCode = EXIT_SQL_FAIL;
			//e.printStackTrace();
		}
		}
		
	}
	
	//
	// Run the specified query
	//
	
	private static void RunQuery(Connection conn, String thisQuery) {
		DB(String.format("Run this: %s", thisQuery));
		
		String detail = "preparing SQL statement";
		String output = "";
		
		try {
			Statement stmt = conn.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY); // This allows us to get a count...
			
			if (isUpdateCommand) {
				detail = "processing update";
				int affectedRows = stmt.executeUpdate(thisQuery);
			}
			else {
				detail = "fetching results";
				ResultSet rs = stmt.executeQuery(thisQuery);
				int numRows = GetRowCount(rs);
				
				DB(String.format("Query returned %s rows", numRows));
				
				if (numRows > 0) {

					//
					// Get the column names from the metadata
					//
					
					detail = "fetching metadata";
					ResultSetMetaData rsm = rs.getMetaData();
					int cols = rsm.getColumnCount();
					
					if (headers) {
						String headerLine = "";
						
						for (int i = 1;i <= cols; i++) {
							String colName = rsm.getColumnName(i);
							String colTypeName = rsm.getColumnTypeName(i);
							int colType = rsm.getColumnType(i);
							//DB(String.format("Col: %s, Type: %s (%s)", colName, colType, colTypeName));
							headerLine = AddString(headerLine, colName, ",");
						}
						
						output = headerLine;
					}
					
					//
					// Loop through the results
					//
					
					while (rs.next()) {
						//
						// Get Each column value for this row
						//
						
						String thisRow = "";
						
						for (int i = 1;i <= cols; i++) {
							String colValue = rs.getString(i);
							
							// 
							// Handle the case where the separator is in the data
							//
							
							try {
								if (colValue.indexOf(sep) > 0) {
									colValue = String.format("\"%s\"", colValue);
								}
							}
							catch (Exception e) {
								DB("Checking colValue for seperator, leaving unchanged");
							}
							
							thisRow = AddString(thisRow, colValue, sep);
						}
						
						output = AddString(output, thisRow, "\n");
					}
					
					//
					// Show results
					//
					
					WO(output);
				} // Some rows found
				else {
					DB("Query returned no rows");
				}
			
			}
			
		}
		catch (SQLException e) {
			WO(String.format("**** Error %s when trying to execute query:\n%s", detail, e.getMessage()));
			ExitCode = EXIT_SQL_FAIL;
			//e.printStackTrace();
		}
		
	}
	
	//
	// See if we have any rows to processing
	//
	
	private static int GetRowCount(ResultSet rs) {
		int numRows = 0;
		
		if (!(rs == null)) {
			//
			// Not empty
			//
			
			String detail = "go last";
			
			try {
				rs.last();
				detail = "get row";
				numRows = rs.getRow();
				detail = "go last";
				rs.beforeFirst();
			}
			catch (SQLException e) {
				//
				// Don't report an error, assume empty
				//
				
				DB(String.format("Failed to get rowcount - %s:\n%s", detail, e.getMessage()));
				ExitCode = EXIT_SQL_FAIL;
				//e.printStackTrace();
			}
			
		}
		
		return numRows;
		
	}
	
	//
	// Process the inputs and make sure we have what we need
	//
	
	private static boolean GetAndCheckInputs(String[] args) {
		boolean returnValue = true;
		String msg = "";
		
		//
		// Get the inputs
		//
		
		server = FindArg(args, "server");
		port = FindArg(args, "port");
		db = FindArg(args, "db");
		user = FindArg(args, "user");
		pwd = FindArg(args, "pwd");
		sid = FindArg(args, "sid");
		dbtype = FindArg(args, "dbtype");
		debug = FindSwitch(args, "debug");
		query = FindArg(args, "query");
		headers = FindSwitch(args, "headers");
		queryFile = FindArg(args, "input");
		help = ((FindSwitch(args, "help")) || (FindSwitch(args, "h")) || (FindSwitch(args, "?")));
		sep = FindArg(args, "sep");
		ignorePort = FindSwitch(args, "noport");
		allowUpdates = FindSwitch(args, "allowupdates");
		
		int dbtypeInt = SetValueFromString(dbtype, MIN_DBTYPE, MAX_DBTYPE, DEFAULT_DBTYPE);
		dbtype = Integer.toString(dbtypeInt);
		dbtypeString = GetDBTypeString(dbtype);
		int portInt= SetValueFromString(port, MIN_PORT, MAX_PORT, GetDBPort(dbtype));
		port = Integer.toString(portInt);
		
		if (server.length() == 0) {
			msg = "No server name was specified";
			returnValue = false;
		}
		
		//if (db.length() == 0) {
		//	msg = AddString(msg, "No database was specified", "\n");
		//	returnValue = false;
		//}
		
		if ((user.length() == 0) && (!(dbtype.equals(DBTYPE_SQL)))) {
			msg = AddString(msg, String.format("For the database type %s (%s), the user must be specified", dbtype, dbtypeString), "\n");
			returnValue = false;
		}
		
		if ((user.length() > 0) && (pwd.length() == 0)) {
			msg = AddString(msg, "The password cannot be empty", "\n");
			returnValue = false;
		}
		
		if (queryFile.length() > 0) {
			//
			// Read the file into "query"
			//
			
			query = "";
			
			try {
				File inputFile = new File(queryFile);
				Scanner rdr = new Scanner(inputFile);
				
				while (rdr.hasNextLine()) {
					String line = rdr.nextLine();
					query += line;
					//WO(String.format("%s\n", line));
				}
				
				rdr.close();
			}
			catch (FileNotFoundException e) {
				msg = AddString(msg, String.format("Unable to locate or read input file. Error: %s", e.getMessage()), "\n");
			}
		}
		
		if ((query.length() == 0) && (queryFile.length() == 0)) {
			msg = AddString(msg, "No Query was provided", "\n");
			returnValue = false;
		}
		
		if ((dbtype == DBTYPE_Oracle) && (sid.length() == 0)) {
			sid = DEFAULT_SID;
		}
		
		if (sep.length() == 0) {
			sep = DEFAULT_Sep;
		}
		
		//
		// Prevent update/delete/insert... decided not to use regular expressions
		//
		
		String[] bad = {"update", "insert", "delete", "alter"};
		boolean found = false;
		
		for (String badWord : bad) {
			
			if (query.toLowerCase().indexOf(badWord) > -1) {
				found = true;
				break;
			}
			
		}

		if (found) {
			
			if (allowUpdates) {
				isUpdateCommand = true;
			}
			else {
				msg = AddString(msg, "The query cannnot be an update/insert/delete", "\n");
				returnValue = false;
			}
			
		}
		
		if (!returnValue) {
			msg = String.format("Invalid inputs provided:\n\n%s", msg);
			ShowHelp();
			WO(msg);
		}
		
		return returnValue;
	}
	
	//
	// Add a string to a string...
	//
	
	private static String AddString(String existingString, String newString, String separator) {
		String returnValue = "";
		
		if (existingString.length() == 0) {
			returnValue = newString;
		}
		else {
			returnValue = String.format("%s%s%s", existingString, separator, newString);
		}
		
		return returnValue;
	}
	
	//
	// Set the string representation of the dbtype
	//
	
	private static String GetDBTypeString(String type) {
		String returnValue = DBTYPE_SQL_String;
		
		switch(type) {
			case DBTYPE_SQL:
				returnValue = DBTYPE_SQL_String;
				break;
			case DBTYPE_Oracle:
				returnValue = DBTYPE_Oracle_String;
				break;
			case DBTYPE_PG:
				returnValue = DBTYPE_PG_String;
				break;
		}
		
		return returnValue;
	}
	
		//
	// Set the string representation of the dbtype
	//
	
	private static int GetDBPort(String type) {
		int returnValue = DEFAULT_SQL_Port;
		
		switch(type) {
			case DBTYPE_SQL:
				returnValue = DEFAULT_SQL_Port;
				break;
			case DBTYPE_Oracle:
				returnValue = DEFAULT_Oracle_Port;
				break;
			case DBTYPE_PG:
				returnValue = DEFAULT_PG_Port;
				break;
		}
		
		return returnValue;
	}
	
	//
	// Make sure a value is in range if it os supposed to be numeric
	//
	
	private static int SetValueFromString(String value, int min, int max, int def) {
		int newValue = 0;
		
		try {
			newValue = Integer.parseInt(value);
		}
		catch (NumberFormatException e) {
			//
			// Invalid string so use the default
			//
			
			newValue = def;
		}
		
		//
		// Make sure that the value is between min and max
		//
		
		if (newValue < min) {newValue = min;}
		if (newValue > max) {newValue = max;}
		
		return newValue;
	}
	
	//
	// Find a switch
	//
	
	private static boolean FindSwitch(String[] args, String switchName) {
		boolean returnValue = false;
		
		//
		// Add - to the switch name to match the inpuit
		//
		
		switchName = String.format("-%s", switchName);
		
		//
		// Loop through the arguments to see if we have it
		//
		
		for (String thisSwitch : args) {
			
			if ((thisSwitch.toLowerCase()).equals(switchName.toLowerCase())) {
				//
				// Found the sqwitch
				//
				
				returnValue = true;
				break;
			} // Found
			
		} // End loop`
		
		return returnValue;
	}
	
	//
	// Find an argument
	//
	
	private static String FindArg(String[] args, String argName) {
		String returnValue = "";
		
		//
		// Add a - to the argName 
		//
		
		argName = String.format("-%s", argName);
		int maxArgs = args.length;
		int i = 0;
		
		//
		// Loop through the arguments looking for the specified one
		//
		
		for (String thisArg : args) {
			
			if (thisArg.toLowerCase().equals(argName.toLowerCase())) {
				//
				// Found the rgument, check to see if thre is another argument after it which we will treat as the value
				//
				
				if (i < (maxArgs -1)) {
					//
					// Set the return value and quit
					//
					
					returnValue = args[i + 1];
				}
				
				break;
			} // Found arg
			
			i += 1;
		} // End loop
		
		return returnValue;
		
	}
	
	//
	// Show some help.. not much
	//
	
	private static void ShowHelp() {	
		WO("");
		WO("Micro Focus OpsBridge generic database query tool");
		WO("");
		WO("The following arguments and switches are supported in any order");
		WO("");
		WO("  -server <server>\tThe database server (host) to connect to (or SERVER\\INSTANCE for SQL instances");
		WO("  -port <port>\t\tThe Port (ignored when a SQL instance is specified)");
		WO("  -db <database>\tThe database or schema to connect to");
		WO("  -user <user>\t\tThe user for connection to the database");
		WO("  -pwd <password>\tThe password for the specified user");
		WO("  -dbtype <type>\tThe server type (1 for MS SQL, 2 for Oracle, 3 for Postgres)");
		WO("  -query \"<query>\"\tQuery to execute");
		WO("  -headers\t\tSwitch - specify this to return the column headers as well as the data");
		WO("  -input <file>\t\tFile containing the query to execute (overrides the -query switch)");
		WO("");
	}
	
	//
	// Debug messgae
	//
	
	private static void DB(String msg) {
		msg = String.format("[DEBUG] %s", msg);
		
		if (debug) {
			WO(msg);
		}
		
	}
	
	//
	// Shorten output from System.out.println to WO
	//
	
	private static void WO(String msg) {
		System.out.println(msg);
	}
	
}
