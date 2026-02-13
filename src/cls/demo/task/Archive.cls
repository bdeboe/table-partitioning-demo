/// This task is scheduled to run on the first Sunday of each month, when system activity is otherwise low
/// For the given table, it moves partitions to different databases based on the date range of the partition
Class demo.task.Archive Extends %SYS.Task.Definition
{

Parameter TaskName = "ArchivePartitions";

/// Default archive partitions older than six months
Property PartitionedTable As %String [ InitialExpression = "demo.logMultiYear" ];

/// Default archive for partitions older than two months
Property ArchiveOlderDatabase As %String [ InitialExpression = "OlderThanTwoYears" ];

/// Default archive for partitions between 1-2 years
Property ArchiveTwoYearDatabase As %String [ InitialExpression = "OneToTwoYears" ];

/// Default archive for partitions between 6-12 months years
Property ArchiveOneYearDatabase As %String [ InitialExpression = "SixToTwelveMonths" ];

/// Do multiple types of archiving
/// Partitions for data older than two years get moved to one database
/// Partitions for data between 1-2 years old get moved to another database
/// Partitions for data between 6-12 months old get moved to yet another database
/// Partitions for data more recent than 6 months remain in the primary database
ClassMethod MovePartitionsToArchivesDynamicSQL(pPartitionedTable As %String, pOlderArchive As %String, pTwoYearArchive As %String, pOneYearArchive As %String) As %Status
{
	// Define our cutoff dates
	set cutoffTwoYear = $SYSTEM.SQL.Functions.DATEADD("year",-2,$ZDATE($HOROLOG,3))
	set cutoffOneYear = $SYSTEM.SQL.Functions.DATEADD("year",-1,$ZDATE($HOROLOG,3))
	set cutoffSixMonths = $SYSTEM.SQL.Functions.DATEADD("month",-6,$ZDATE($HOROLOG,3))

	// Partitions for data older than two years get moved to OlderThanTwoYears
	set sql = "ALTER TABLE "_pPartitionedTable_
          " MOVE PARTITION BETWEEN '1900-01-01' AND '"_cutoffTwoYear_"' "_
          " TO '"_pOlderArchive_"'"
	set rset = $SYSTEM.SQL.Execute(sql)
	if (rset.%SQLCODE '= 0) {write "%Execute failed:", !, "SQLCODE ", rset.%SQLCODE, ": ", rset.%Message return rset}

	// Partitions for data between 1-2 years old get moved to OneToTwoYears
	set sql = "ALTER TABLE "_pPartitionedTable_
          " MOVE PARTITION BETWEEN '"_cutoffTwoYear_"' AND '"_cutoffOneYear_"' "_
          " TO '"_pTwoYearArchive_"'"
	set rset = $SYSTEM.SQL.Execute(sql)
	if (rset.%SQLCODE '= 0) {write "%Execute failed:", !, "SQLCODE ", rset.%SQLCODE, ": ", rset.%Message return rset}

	// Partitions for data between 6-12 months old get moved to SixToTwelveMonths
	set sql = "ALTER TABLE "_pPartitionedTable_
          " MOVE PARTITION BETWEEN '"_cutoffOneYear_"' AND '"_cutoffSixMonths_"' "_
          " TO '"_pOneYearArchive_"'"
	set rset = $SYSTEM.SQL.Execute(sql)
	if (rset.%SQLCODE '= 0) {write "%Execute failed:", !, "SQLCODE ", rset.%SQLCODE, ": ", rset.%Message return rset}

	return $$$OK
}

/// Default purge code 
Method OnTask() As %Status
{
	return ..MovePartitionsToArchivesDynamicSQL(..PartitionedTable, ..ArchiveOlderDatabase, ..ArchiveTwoYearDatabase, ..ArchiveOneYearDatabase)
}

/// Populate a demo.log* table with entries spanning many days, with one entry per day
/// pTableName: the table you're inserting log entries into
/// pStartDate: With today's date as zero, what date should we start at? 
/// 		To start in the past, use a negative value
/// pEndDate: With today's date as zero, what date should we end at? 
/// 		To end in the past, use a negative value
/// Example: Starting from 1000 days in the past and going until 100 days into the future, add one log entry per day
/// 		set tSC = ##class(Test.Ben.TBLP.Task.Archive).InsertLogEntriesDateRange("demo.logMultiYear",-1000,100)
ClassMethod InsertLogEntriesDateRange(pTableName As %String = "demo.logMultiYear", pStartDate As %Integer = 1, pEndDate As %Integer = 10) As %Status [ Language = objectscript ]
{
	SET stmt = ##class(%SQL.Statement).%New()
	set status = stmt.%Prepare("INSERT INTO "_pTableName_"(ts, log_level, message) VALUES (?, ?, ?)")
	if $$$ISERR(status) {
		do $system.OBJ.DisplayError(status)
		return status
	}

	TSTART

	FOR i=pStartDate:1:pEndDate {
    	SET ts = $ZDATETIME($HOROLOG+i,3)
    	set logTable = stmt.%Execute(ts, "INFO", "Synthetic log message #" _ i)
		if logTable.%SQLCODE < 0 {
			write logTable.%SQLCode
			return logTable
		}
	    // Commit every 10k rows
    	IF '(i#10000) {
        	TCOMMIT
			TSTART
    	}
	}
	TCOMMIT
	return $$$OK
}

}
