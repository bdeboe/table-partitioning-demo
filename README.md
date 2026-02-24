# Table Partitioning Demo

This demo walks you through the new Table Partitioning feature in IRIS SQL, explaining what it does and how it works along the way. We'll only use a few dozen rows to prove the concept, but obviously the capability is focused on datasets many orders of magnitude larger. 

<!--
:information_source: While an experimental version of the new capability was first made available with IRIS 2025.2, we recommend users download the more recent kits and containers made available through the [Early Access Program](https://www.intersystems.com/early-access-program/) to explore this new capability. For more about what's new in the current version, see [below](#version-history) 
-->
:information_source: While some Table Partitioning features were first made available with IRIS 2025.2, we recommend users download the more recent kits and containers made available through the [IRIS 2026.1 Developer Preview](https://community.intersystems.com/post/third-intersystems-iris-intersystems-iris-health-and-healthshare-health-connect-2026-1) to explore this new capability. For more about what's new in the current version, see [below](#version-history) 


## What is Table Partitioning?

Table Partitioning helps users manage large tables efficiently by enabling them to split the data across multiple databases based on a logical scheme. This enables, for example, moving older data to a database mounted on a cheaper tier of storage, while keeping the current data that is accessed frequently on premium storage. The data structure for partitioned tables also brings several operational and performance benefits when tables get very large (> 1B rows).

For more about the what and how of Table Partitioning, please check the [Frequenty Asked Questions](#frequently-asked-questions) section at the bottom of this page.


## Getting Started
<!--
You can download a kit or container image in the Table Partitioning EAP section of the [Evaluation Portal](https://evaluation.intersystems.com/), and install or start it just like any other IRIS instance. Once installed, you can use your favourite SQL interface (DBeaver, the Shell, or the SMP) to run the commands described in this tutorial.
-->
The latest version of Table Partitioning is available in the [IRIS 2026.1 Developer Preview](https://community.intersystems.com/post/third-intersystems-iris-intersystems-iris-health-and-healthshare-health-connect-20261-developer). You can download a kit or container image from that page, and you can install or start it just like any other IRIS instance. Once installed, you can use your favourite SQL interface (DBeaver, the Shell, or the SMP) to run the commands described in this tutorial.

### Creating the test namespace

I like to begin by creating a test namespace and database that we can use for our demo. I named mine TESTTP1. If you're feeling lazy, you can just use the built-in USER namespace for this demo; it will work just as well.
>    Home > Menu > Configure Namespaces > Create New Namespace

### Creating databases

The main goal of Table Partitioning is to enable administrators to split table data across multiple databases to simplify operations, so we'll want to create a few databases first. For this purpose, we'll use a new flavour of the existing `CREATE DATABASE` command - which would create an entire _namespace_ - to just create the local database:

```SQL
CREATE DATABASE FILE "data-2024";
CREATE DATABASE FILE "data-2023";
CREATE DATABASE FILE "archive" ON DIRECTORY '{install dir}/mgr/cheap/archive/';  -- change to match your setup
```

This will create three additional databases using default settings, but no namespace is mapping anything to them just yet.

### Creating a partitioned table

In Table Partitioning, we distinguish between _how_ you partition your data and _where_ the partitions are stored. The first bit defines the underlying data structure (global subscripts, see [below](#how-does-it-work)) and is part of your table definition -- in other words, part of the code. The latter is more a runtime thing, specific to the instance, that may differ depending on where you're deploying your application to.

The _how_ part is specified through a *partition key*, which defines a field in the table and a scheme to derive an actual "partition" based on the field's value for every row. The available partition schemes are:
* Range partitioning - for example, splitting table data based on a `date_created` field, with each partition corresponding to one month (the _interval_ for the range partition key)
* List partitioning - for example, splitting table data based on a `region` field, with each partition corresponding to exactly one region
* Hash partitioning - for example, splitting table data based on a `customer_id` field, with data distributed across a fixed number of partitions based on a hash of the `customer_id` column
Composite partition keys are also supported, in which case you can choose a partition scheme for each field independently.

As a first example, we'll create a simple transaction log table that is partitioned by date:
```SQL
CREATE TABLE demo.log (
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    log_level VARCHAR(10) DEFAULT 'INFO',
    message VARCHAR(1000)
) PARTITION BY RANGE (ts) INTERVAL 1 MONTH;

CREATE BITMAP INDEX levelBIdx ON demo.log(log_level);
```

That's it! We have now created our first partitioned table, and any data we'll write to the table will automatically be structured into a partition for the month represented by `ts`. 
Let's add a few rows to see what this means:

```SQL
INSERT INTO demo.log (message) VALUES ('this is today''s first message');
INSERT INTO demo.log (message) VALUES ('this is today''s second message');
INSERT INTO demo.log (log_level, message) VALUES ('ERROR', 'this is an error message, sadly');
INSERT INTO demo.log (ts, message) VALUES (DATEADD('month', 6, CURRENT_TIMESTAMP), 'a message from the future!');
INSERT INTO demo.log (ts, log_level, message) VALUES (DATEADD('month', 6, CURRENT_TIMESTAMP), 'FATAL', 'it''s the end of the world as we know it');
INSERT INTO demo.log (ts, log_level, message) VALUES ('2024-08-12', 'INFO', 'Enjoy the Perseid meteor shower!');
```

We can now consult the catalog to see our partitions, either using the new view in the SMP's table details section, or by querying the catalog directly:

```SQL
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS;
```

This query should return 3 rows -- one for the current month, one for those two future records (as per the `DATEADD()` function call), and one of the past record from August 2024 -- with the location where the partitions are stored. As you'll see, they're all located in the TESTTP1 database, which is the default for the TESTTP1 namespace. This is because thus far, we've only specified _how_ the table data should be partitioned, and not _where_ to map it to. The _where_ is achieved through a tool called the *Extent Mapper*.

### The Extent Mapper

:information_source: _Before we can successfully run the MOVE PARTITION commands below, we'll need to go to Jouranl Settings and make sure that "Journal freeze on error" is enabled._ 
>    Home > System Administation > Configuration > System Configuration > Journal Settings

The Extent Mapper helps you map partitions to databases other than the default one for a given namespace. It comes with a set of straightforward SQL commands. With the following command, we'll map all data for partitions covering 2023 to the `data-2023` database, and data for partitions earlier than that to the `archive` database:
```SQL
ALTER TABLE demo.log MOVE PARTITION BETWEEN '2023-01-01' AND '2023-12-31' TO "data-2023";
ALTER TABLE demo.log MOVE PARTITION BETWEEN '2000-01-01' AND '2022-12-31' TO "archive";
```

In the above command, the `BETWEEN` keyword is used to specify a date range, because the partition key for our table is using range partitioning. The values we specified are used to identify the first and last partition to move. Please refer to the documentation for more on the specific syntax for other partition schemes.

When working from the catalog info we used before, you can also specify the partition IDs directly, using individual values or a range (when using range partitioning):
```SQL
ALTER TABLE demo.log MOVE PARTITION ID '202411010000' TO "data-2024";
ALTER TABLE demo.log MOVE PARTITION ID BETWEEN '202401010000' AND '202412010000' TO "data-2024";
```

If you consult the catalog table we used earlier again, you'll notice one important change. The entry with PARTITION_ID = 202408010000 now shows LOCATION = DATA-2024
```SQL
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS;
```
This demonstrates the "move" part of MOVE PARTITION. The command first maps the partitions to your desired databases, and then it physically moves any relevant data from the source database to the target database. 

However, you'll also notice that the catalog table does not show any information for the DATA-2023 database or the ARCHIVE database. This is because a partition only exists when there's actual data in it. A separate catalog table exists to show the current mappings themselves:
```SQL
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITION_MAPPINGS;
```

Now let's add some data for these periods, and verify the data went into the right database:
```SQL
INSERT INTO demo.log (ts, log_level, message) VALUES ('2014-02-27', 'INFO', 'this happened over a decade ago!');
INSERT INTO demo.log (ts, log_level, message) VALUES ('2023-01-01', 'INFO', 'Happy 2023!!');
INSERT INTO demo.log (ts, log_level, message) VALUES ('2024-12-25', 'INFO', 'Merry Christmas!!');
INSERT INTO demo.log (ts, log_level, message) VALUES ('2020-04-12', 'INFO', 'Happy Easter!!');

SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS;
```
You should now see how the records (partitions) ended up in the right database. As we haven't specified a mapping for the 2025 and 2026 data, those records continue to go into the namespace's default database, though nothing prevents us from specifying a mapping for current or future records upfront.

### Other partition-level operations

In addition to moving partitions using the Extent Mapper, we're also introducing commands to drop entire partitions, including their database mappings:
```SQL
ALTER TABLE demo.log DROP PARTITION ID '201402010000';
  -- the 2014 entry "this happened over a decade ago!" is now gone
ALTER TABLE demo.log DROP PARTITION BETWEEN '2000-01-01' AND '2020-12-31';
  -- the 2020 entry "Happy Easter!!" is now gone

SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS;
  -- the two ARCHIVE entries (PARTITION_IDs = 201402010000 and 202004010000) are now gone
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITION_MAPPINGS;
  -- but the mapping for the ARCHIVE is still there
```

:information_source: This DROP PARTITION command is meant to be used by administrators only, as it skips journaling, locking, triggers, and does not take referential action. 


### Querying partitioned tables

You can query partitioned tables just like any other table. When a filter predicate in the `WHERE` clause of a query concerns a partition key field, IRIS SQL will verify whether it can be used to limit the number of partitions to look into to build the query result set. This is called _partition pruning_ and will typically result in an additional range condition or parallelization level in the query plan.

Let's see how this looks with an example. Use the "Show Plan" button in the SMP or the `EXPLAIN` command in your shell or JDBC tool to check the query plan for the following query:

```SQL
SELECT * FROM demo.log WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-12-31 23:59:59';
```

You should see something like this:

![Query plan](/img/query-plan-1.png)

We have translated the range condition on our `ts` field from the query into a range condition on the master map's subscript structure (more about that [later](#under-the-hood)). This may not look like much at first as you'd see this all the time for conditions on indexed fields. What's different is that this time we haven't defined an index on `ts` at all. We're just exploiting the partitioned structure of the master map to turn this full table scan into a full scan of a much smaller set of partitions, excluding the ones that certainly don't contain data matching our `ts` condition.

Let's look at another query:

```SQL
SELECT COUNT(*) FROM demo.log WHERE ts BETWEEN '2024-01-01 00:00:00' AND '2024-12-31 23:59:59' AND log_level IN ('FATAL', 'ERROR');
```

and it's query plan:

![Query plan](/img/query-plan-2.png)

What's new here is that it's leveraging the same partition pruning trick we used for the master map in the previous example, but now for its use of the index on `log_level`. This is because we apply the same partitioned structure to indices, which of course is necessary in order to support mapping index data along with row data as described earlier. 

:information_source: Index partitioning is now also available for the Approximate Nearest Neighbour index used for [Vector Search](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_vectorsearch). In that index, we build a complex graph based on the vector data, and search performance decreases as the graph gets large. Thanks to the bucketed nature of partitioned tables, there's a maximum size to this graph and we can efficiently search through buckets in parallel. 


### Under the hood

Thus far, we've looked at the SQL surface only. Assuming you're somewhat familiar with how IRIS stores table data in globals, let's look at what happens under the hood. If you think of the word "global" as a type of warming, feel free to skip straight to the [next section](#how-to-convert-existing-data).

#### Table data

By default, IRIS stores table data in a simple global structure with an integer as the subscript representing the row ID, and a `$listbuild` containing column data:
```ObjectScript
^demo.log( <row-ID> ) = $lb( <column-1>, <column-2>, ... )
```
:information_source: Note that the name of this global in practice will look a little different - we hash the schema and table pieces for certain low-level efficiencies - but that'd only make this example less readable. See the doc on [extent sets](https://docs.intersystems.com/iris20243/csp/documatic/%25CSP.Documatic.cls?LIBRARY=%25SYS&CLASSNAME=%25Library.Persistent#USEEXTENTSET) for more details.

In order to organize data into partitions, and map those partitions to databases using the Extent Mapper, we need to introduce an additional subscript level that encodes the partition field values into a partition ID that is easily mappable. For example, in our range partitioning case, we're simply encoding the date into a straightforward integer format. 
The following structure would achieve that basic goal:
```ObjectScript
^demo.log( <partition-ID>, <row-ID> ) = $lb( <column-1>, <column-2>, ... )
```

However, in this model individual partitions can still grow arbitrarily large, and pose some of the same issues we're having with large non-partitioned tables today, including lock escalation, unwieldy indices, etc. For these reasons, we're splitting each partition into *buckets* that have a predictable maximum size of about 2 million rows (32*64,000 to be precise). Based on our benchmarks, this bucket size offers a good balance between parallelism opportunities and overhead, and aligns well with our bitmap and columnar data structures.
Also, we'll switch from a table wide identifier as the last subscript to an integer that's only unique within the partition, ensuring the fastest possible throughput for each partition. This means the row ID becomes a composite ID, combining the partition ID with that integer (we'll call PRowID):
```ObjectScript
^demo.log( <partition-ID>, <bucket-ID>, <P-row-ID> ) = $lb( <column-1>, <column-2>, ... )
```
If you navigate to the table's maps and indices and then select the master map global, or just consult the global directly, you'll see what this comes down to for our table:
```ObjectScript
^DvH1.Ccdz.1	=	""
^DvH1.Ccdz.1(202301010000)	=	1
^DvH1.Ccdz.1(202301010000,1,1)	=	$lb(1154594035806846976,"INFO","Happy 2023!!")
^DvH1.Ccdz.1(202412010000)	=	1
^DvH1.Ccdz.1(202412010000,1,1)	=	$lb(1154656589406846976,"INFO","Merry Christmas!!")
^DvH1.Ccdz.1(202501010000)	=	3
^DvH1.Ccdz.1(202501010000,1,1)	=	$lb(1154658438312846976,"INFO","this is today's first message")
^DvH1.Ccdz.1(202501010000,1,2)	=	$lb(1154658438313846976,"INFO","this is today's second message")
^DvH1.Ccdz.1(202501010000,1,3)	=	$lb(1154658438314846976,"ERROR","this is an error message, sadly")
^DvH1.Ccdz.1(202507010000)	=	2
^DvH1.Ccdz.1(202507010000,1,1)	=	$lb(1154674076715846976,"INFO","a message from the future!")
^DvH1.Ccdz.1(202507010000,1,2)	=	$lb(1154674076716846976,"FATAL","it's the end of the world as we know it")
```

We're only working with a handful of rows, all fitting into a single bucket per partition, but with this structure, we are ready to efficiently manage tables well into the billions if not trillions of rows.

#### Indices

Before we released this feature, some customers have manually mapped ranges of (classic) row IDs to different databases as a form of partitioning (we're not blaming them - they should blame us for not releasing this earlier!). This can help address the most pressing need to split table data, but it does not give you much control over what data actually gets mapped (contrast the randomness of row IDs with per-month partitions) and does not offer a solution for indices because they don't have any predictable subscript structure to base your mappings on at all.

Let's first look at how a simple index on our log table's `log_level` field looks today:
```ObjectScript
^demo.log.lvl( <log-level-value>, <row-ID> ) = "" // regular
^demo.log.lvb( <log-level-value>, <chunk> ) = $bit(...) // bitmap
```

In the new model, this becomes:
```ObjectScript
^demo.log.lvl( <partition-ID>, <bucket-ID>, <log-level-value>, <P-row-ID> ) = "" // regular
^demo.log.lvb( <partition-ID>, <bucket-ID>, <log-level-value>, <chunk> ) = $bit(...) // bitmap
```

And for our table's bitmap index in practice:
```ObjectScript
^DvH1.Ccdz.3(202301010000,1," INFO",1)	=	/* $bit(2) - PRowIDs: 1 */
^DvH1.Ccdz.3(202412010000,1," INFO",1)	=	/* $bit(2) - PRowIDs: 1  */
^DvH1.Ccdz.3(202501010000,1," ERROR",1)	=	/* $bit(4) - PRowIDs: 3  */
^DvH1.Ccdz.3(202501010000,1," INFO",1)	=	/* $bit(2,3) - PRowIDs: 1,2  */
^DvH1.Ccdz.3(202507010000,1," FATAL",1)	=	/* $bit(3) - PRowIDs: 2  */
^DvH1.Ccdz.3(202507010000,1," INFO",1)	=	/* $bit(2) - PRowIDs: 1  */
```

You may have noticed that, for simple index lookups such as to enforce uniqueness, the above structure requires looping through all partitions and buckets. This is indeed a price we pay for the scalability we gain, and one we're mitigating through appropriate use of parallelism. Obviously, when your index or uniqueness constraint also includes the partition key fields, that overhead no longer applies.

#### The namespace mappings

Earlier, we talked about how MOVE PARTITION first maps the partitions to your desired databases. You can see these mappings yourself in the Global Mappings page. You should see the globals split acording to their partition subscripts, with each split assigned to the appropriate database.
>    Home > Menu > Configure Namespaces > Global Mappings (for the TESTTP1 row)

#### The class definition

While we're presenting this new capability from the SQL perspective, the partition key and other elements relevant to the partitioning configuration can all be expressed through UDL. 

For the `demo.log` table described in this tutorial, the following members are created in the class definition (we removed some nonspecific elements for readability):

```ObjectScript
Class demo.log Extends %Persistent
{

/* ... */

/// Bucket Id Property, auto-generated for partitioned class
Property "%%BUCKETID" As %Library.BigInt [ Private, SqlComputeCode = {set {*}={x__prowid}\2048000+1}, SqlComputed, SqlFieldName = x__bucketid ];

/// Partition Id 1 property, auto-generated for partitioned class
Property "%%PARTITIONID1" As %Library.Integer [ Private, SqlComputeCode = {set {*}=$$partitionIdFromDateTime^%occPartition({ts},"%Library.PosixTime",1,"MONTH")}, SqlComputed, SqlFieldName = x__partitionid1 ];

/// Partition-RowId property, auto-generated for partitioned class
Property "%%PROWID" As %Library.BigInt [ Private, SqlComputeCode = {set {*}=$sequence(^DvH1.Ccdz.1({x__partitionid1}))}, SqlComputed, SqlFieldName = x__prowid ];

/// Partition IdKey, auto-generated for partitioned class
Index "%%PartitionIdKey1" On ("%%PARTITIONID1", "%%BUCKETID", "%%PROWID") [ IdKey, Unique ];

/// PartitionKey index, auto-generated by DDL CREATE TABLE statement
Index PartitionKey On logts(range(1 month) [ Abstract, SqlName = "%%PartitionKey" ];

/* ... */

}
```

:information_source: As you can imagine, these specific class members should not be modified.


### How to convert existing data?
 
As of the December 2025 pre-release kits, we now have the ability to partition a table that is not already partitioned. Similarly, we have the ability to de-partition a table that is partitioned. Let's start by essentially recreating our demo.log table, but this time without the PARTITION BY clause
 
```SQL
CREATE TABLE demo.log2NotPart (
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    log_level VARCHAR(10) DEFAULT 'INFO',
    message VARCHAR(1000)
);
```
 
And let's insert our same data into this table
 
```SQL
INSERT INTO demo.log2NotPart (log_level, message) VALUES ('ERROR', 'this is an error message, sadly');
INSERT INTO demo.log2NotPart (ts, message) VALUES (DATEADD('month', 6, CURRENT_TIMESTAMP), 'a message from the future!');
INSERT INTO demo.log2NotPart (ts, log_level, message) VALUES (DATEADD('month', 6, CURRENT_TIMESTAMP), 'FATAL', 'it''s the end of the world as we know it');
INSERT INTO demo.log2NotPart (ts, log_level, message) VALUES ('2024-08-12', 'INFO', 'Enjoy the Perseid meteor shower!');
INSERT INTO demo.log2NotPart (ts, log_level, message) VALUES ('2014-02-27', 'INFO', 'this happened over a decade ago!');
INSERT INTO demo.log2NotPart (ts, log_level, message) VALUES ('2023-01-01', 'INFO', 'Happy 2023!!');
INSERT INTO demo.log2NotPart (ts, log_level, message) VALUES ('2024-12-25', 'INFO', 'Merry Christmas!!');
INSERT INTO demo.log2NotPart (ts, log_level, message) VALUES ('2020-04-12', 'INFO', 'Happy Easter!!');
```
 
If we check our handy catalog table, we'll see that there is no mention of demo.log2NotPart. This is expected, since the table is not partitioned.
 
```SQL
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS;
```
 
Now let's use our CONVERT PARTITION command to partition our new table
 
```SQL
ALTER TABLE demo.log2NotPart CONVERT PARTITION BY RANGE (ts) INTERVAL 1 MONTH
```
 
When we re-query our catalog table, we should now see seven PARTITION_ID entries for demo.log2NotPart
 
 
We can also de-partition the table by using the CONVERT PARTITION OFF command
```SQL
ALTER TABLE demo.log2NotPart CONVERT PARTITION OFF
```
 
Once again, when we re-query our catalog table, we should once again see only the partitions for demo.log.
 
There is a bit more nuance to partition conversion than we demonstrated here. If you're trying out this feature, refer to [this question](#can-i-convert-my-existing-tables-to-use-partitioning) in the FAQ section. 


### Auto-archiving older partitions - demo

Earlier in this demo, we demonstrated how `ALTER TABLE ... MOVE PARITION` could be used to move partitions to a specified database, such as an archive database. We can use this in conjunction with the [IRIS Task Manager](https://docs.intersystems.com/iris20253/csp/docbook/Doc.View.cls?KEY=GSA_manage_taskmgr) to auto-archive older partitions. In the `src/cls` source code folder of this repository, you'll find a class `demo.task.Archive` that demonstrates what that could look like. Let's start by once again recreating our demo.log table, but this one will hold a few years worth of entries.
 
```SQL
CREATE TABLE demo.logMultiYear (
    ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    log_level VARCHAR(10) DEFAULT 'INFO',
    message VARCHAR(1000)
) PARTITION BY RANGE (ts) INTERVAL 1 MONTH;
```
 
And let's once again create a few extra databases

```SQL
CREATE DATABASE FILE "OlderThanTwoYears" ON DIRECTORY '{install dir}/mgr/cheap/archive/';  -- change to match your setup
CREATE DATABASE FILE "OneToTwoYears";
CREATE DATABASE FILE "SixToTwelveMonths";
```

Using VS Code or using `$SYSTEM.OBJ.Load()` from the IRIS Terminal, import that Archive Task class into our TESTTP1 namespace. In addition to the usual task methods, it includes a classmethod that can populate your table with years' worth of entries. From an IRIS Terminal, run the following command. It will populate entries in the table, starting from 1000 days in the past and going until 100 days into the future, adding one log entry per day.

```csharp
set tSC = ##class(demo.task.Archive).InsertLogEntriesDateRange("demo.logMultiYear",-1000,100)
```
 
Check the demo.logMultiYear table and our handy catalog table. You should see the log entries, and you should see that the data is spread across dozens of partitions.
 
```SQL
SELECT TOP 1000 * FROM demo.logMultiYear;
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS WHERE TABLE_NAME = 'logMultiYear';
```

Now, let's set up that auto-archiving task:  
1) In the System Management Portal, go to Home > System Operation > Task Manager > New Task  
2) Give it a name like ArchiveDemoLogPartitions  
3) In the "Namespace to run task in" dropdown, select TESTTP1  
4) For the Task Type, select ArchivePartitions  
5) If you used the same table name and database names as this demo, you can leave the rest of the default values as-is  
6) Click Next  
7) Set the task to run "Monthly (by day)", and have it run Every 1 month(s) on the First Sunday  
8) Have it run once at the time 00:01:00  
9) Click Finish  

The auto-archiving task is now scheduled to run once per month, on the first Sunday of each month, at 1:00am.  
I'm a bit impatient though, so let's run the task now and see what happens.  

1)  Go to Home > System Operation > Task Manager > Task Schedule  
2)  Click on the entry for ArchiveDemoLogPartitions  
3)  Click Run, then Performa Action Now, then Close  
4)  The task may take up to two minutes to start running, and it may take another 1-4 minutes to complete.  
5)  Refresh the page until you see that "Last Finished" is populate with a timestamp  
6)  Once again, check the demo.logMultiYear table and our handy catalog table. The catalog table should show that the older partitions now have a LOCATION that corresponds with the approprate older databases.  

```SQL
SELECT TOP 1000 * FROM demo.logMultiYear;
SELECT * FROM INFORMATION_SCHEMA.TABLE_PARTITIONS WHERE TABLE_NAME = 'logMultiYear';
```

That's it! You've just set up an automatic archiving task that moves older partitions to cheaper storage. This is of course just a demonstration, and in your production deployment you may have specific constraints that differ from our TESTTP1 scenario, but as you'll appreciate from the `demo.task.Archive` class, the key work is all performed by `ALTER TABLE ... MOVE PARTITION` commands we're just constructing based on the goals and constraints of our use case.


### Cleaning up

A simple `DROP TABLE` command will automatically remove any database mappings created through the Extent Mapper, so the following is all we have to do to clean up our table:
```SQL
DROP TABLE IF EXISTS demo.log;
DROP TABLE IF EXISTS demo.log2NotPart;
DROP TABLE IF EXISTS demo.logMultiYear;
```


## Frequently Asked Questions

### Who needs Table Partitioning?

Most applications or schemas where data accumulates over time (or starts off big!) will benefit from adopting Table Partitioning. It is especially relevant to customers who are concerned about the cost of hosting their whole database on premium storage, just because a slice of that database is "hot data" that needs to be available at the ultra-low latency offered by that premium storage tier.

### Does this offer fully automatic storage tiering?

The Table Partitioning capability described here will start off as a platform feature and offers the tools for an administrator to define an information lifecycle policy that includes moving data between storage tiers and archiving old partitions, but does not magically automate this process. Such automation requires more knowledge about the environment, not least about the available storage tiers and overall intent. Our cloud services, where we control that environment, are better positioned to (and will) deliver that kind of automation layer on top of the platform-level feature.

### When will this feature be available with InterSystems IRIS?

You can try the new capability through the [Early Access Program](https://www.intersystems.com/early-access-program/) now, and we hope to include it in an IRIS release early in 2026.

### How does it work?

At a technical level, Table Partitioning relies on additional leading subscripts that encode the partition key value, used universally for row data, indices, and other associated data structures. At schema design time, users can pick a partition key such as a date field or region, and how that field's values should translate to partitions, such as monthly date ranges, or a single partition per region. When rows are added to a partitioned table, the SQL (or Object) Filer will calculate the proper subscript values for each row and make sure data ends up in the right place. Using a new tool called the Extent Mapper (available through simple DDL commands), users can then map or move partitions from one database to another using logical criteria, such as moving all the partitions for 2021 to one database and those for 2022 to another. 

### Couldn't I do this already with subscript-level mappings?

To some extent, yes. In fact, Table Partitioning relies on subscript-level mappings to wire data to the right place, but the big difference is that it introduces those additional subscripts the mappings are based on and allows you to express the mapping in logical terms, relevant to what you defined as a partition scheme. Prior to this, users could only manually create mappings based on the RowID, which has no logical meaning beyond a wild approximation of record age, and had no way whatsoever to meaningfully split index globals.

### Can I convert my existing tables to use partitioning?

Yes, we're including `ALTER TABLE .. CONVERT ..` syntax to allow [transforming an existing table into a partitioned table](https://github.com/bdeboe/table-partitioning-demo?tab=readme-ov-file#how-to-convert-existing-data) and vice versa. Note that some conversions imply a change to the RowID and may require updates to tables with a foreign key constraint pointing to the table being converted.

### What other benefits should I expect?

The more refined data structure offers two additional benefits, beyond the ability to easily organize your data across databases:

* thanks to the additional subscript level, large-scale ingestion can get faster as there's less chance of lock escalation and overall contention
* the query optimizer can build smarter query plans when it detects predicates involving the partition key field, for example pruning (skipping) partitions for which it knows there can't be any matching rows. 

### Where's the catch?

The additional subscript level causes overhead in the context of unique keys that do not include the partition key fields. When filing new rows, checking whether the new row's value doesn't exist yet requires checking every partition. Similarly, a lookup based on a unique key value will require looping over all partitions. We plan to add support for global indices that are not partitioned and help with truly unique fields, but those of course also cannot be split across databases.

### What are buckets?

You may not always have a perfect candidate for a partition key, yet want to benefit from the operational advantages brought by the additional subscript level with respect to ingestion, or simply want to move "some" of a large table's data to another database without using a specific logical constraint. For partitioned tables, we do not only introduce a subscript level that encodes the partition key, but also an opaque "bucket ID" that helps organize data in smaller portions, regardless of whether your partition key is fine-grained, balanced, or neither. A "bucketed" table is a table that adopts this additional subscript level, but does not have a logical partition key defined on top of that, and therefore offers you some of the advantages of partitioned tables with no further design-time choices required. Long-term, we intend to make bucketing the default when creating a new table.

### How does this relate to sharding?

Table Partitioning is fully orthogonal to sharding. 

While the two at first may sound similar, because they're focused on very large tables, the reasons to use partitioning are mostly operational, whereas sharding is purely focused on performance. Also, you choose a partition key to be able to map specific partitions to databases based on the partition key value, whereas in the case of sharding the distribution of data between shards is 100% opaque and you'd only choose a key to ensure cosharding relationships between tables that are frequently JOINed.

Note that combining partitioning with sharding adds a little more complexity because the databases you'd be mapping to need to be available on each shard.

### How does this relate to columnar storage?

Table Partitioning is fully orthogonal to columnar storage, and we expect customers implementing a data warehouse and similar scenarios will often use them together.

### How about our other data models?

The feature is currently called _Table_ Partitioning, but we may expand the principle to other data models in the future, where there's a need to logically organize data across multiple databases.

## Version History

The following versions have been published through the EAP

* 2025.2.0TBLP.111
  * Initial filer and query support
  * Support for mapping empty partitions

* 2025.3.0TBLP.101
  * Initial version of partition pruning
  * Partitioned ANN index
  * Various bugfixes and smaller enhancements

* 2026.1.0TBLP.111
  * MOVE PARTITION now supporting non-empty partitions
  * Partitioned ANN index
  * Various bugfixes and smaller enhancements
    
* 2026.1 Developer Preview (February 2026)
  * Container images are easier to deploy
  * Various bugfixes and smaller enhancements

## How to get help?

Please use the [Issues](issues) section in this repository if you have questions about the tutorial, or ask your questions on the [Developer Community](htttps://community.intersystems.com/)
