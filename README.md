# Table Partitioning Demo

This demo walks you through the new Table Partitioning feature in IRIS SQL. 

:information_source: Please note that, for now, the new capability is only available with IRIS kits and containers made available through the [Early Access Program](https://www.intersystems.com/early-access-program/).

## What is Table Partitioning?

Table Partitioning helps users manage large tables efficiently by enabling them to split the data across multiple databases based on a logical scheme. This enables, for example, moving older data to a database mounted on a cheaper tier of storage, while keeping the current data that is accessed frequently on premium storage. The data structure for partitioned tables also brings several operational and performance benefits when tables get very large (> 1B rows).

For more about the what and how of Table Partitioning, please check the [Frequenty Asked Questions](#frequently-asked-questions) section at the bottom of this page.

## Getting Started

You can download a kit or container image in the Table Partitioning EAP section of the [Evaluation Portal](https://evaluation.intersystems.com/), and install or start it just like any other IRIS instance. Once installed, you can use your favourite SQL interface (DBeaver, the Shell, or the SMP) to run the commands described in this tutorial.

### Creating databases

The main goal of Table Partitioning is to enable administrators to split table data across multiple databases to simplify operations, so we'll want to create a few databases first. For this purpose, we'll use a new flavour of the existing `CREATE DATABASE` command - which would create an entire _namespace_ - to just create the local database:

```SQL
CREATE DATABASE FILE "data-2024";
CREATE DATABASE FILE "data-2023";
CREATE DATABASE FILE "archive" ON DIRECTORY '/cheap/archive';  -- change to match your setup
```

This will create three additional databases using default settings, but no namespace is mapping anything to them just yet.

### Creating a table

In Table Partitioning, we distinguish between how you partition your data, and where the partitions are stored. The first bit defines the underlying data structure (global subscripts, see [below](#how-does-it-work)) and is part of your table definition, in other words part of the code. The latter is more a runtime thing, specific to the instance, that may differ depending on where you're deploying your application to.

The _how_ part is specified through a *partition key*, which defines a field in the table and a scheme to derive an actual "partition" based on the field's value for every row. The available partition schemes are:
* Range partitioning - for example, splitting table data based on a `date_created` field, with each partition corresponding to one month (the _interval_ for the range partition key)
* List partitioning - for example, splitting table data based on a `region` field, with each partition corresponding to exactly one region
* Hash partitioning - for example, splitting table data based on a `customer_id` field, with data distributed across a fixed number of partitions based on a hash of the `customer_id` column
Composite partition keys are also supported, in which case you can choose a partition scheme for each field independently.

As a first example, we'll create a simple transaction log table that is partitioned by date:
```SQL
CREATE TABLE demo.log (
    log_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    log_level VARCHAR(10) DEFAULT 'INFO',
    message VARCHAR(1000)
) PARTITION BY RANGE (log_ts) INTERVAL 1 MONTH;

CREATE BITMAP INDEX levelBIdx ON demo.log(log_level);
```

That's it! We have now created our first partitioned table, and any data we'll write to the table will automatically be structured into a partition for the month represented by `log_ts`. 
Let's add a few rows to see what this means:

```SQL
INSERT INTO demo.log (message) VALUES ('this is today''s first message');
INSERT INTO demo.log (message) VALUES ('this is today''s second message');
INSERT INTO demo.log (log_level, message) VALUES ('ERROR', 'this is an error message, sadly');
INSERT INTO demo.log (log_ts, message) VALUES (DATEADD('month', 6, CURRENT_TIMESTAMP), 'a message from the future!');
INSERT INTO demo.log (log_ts, log_level, message) VALUES (DATEADD('month', 6, CURRENT_TIMESTAMP), 'FATAL', 'it''s the end of the world as we know it');
```

We can now consult the catalog to see our partitions, either using the new view in the SMP, or by querying the catalog query directly:

```SQL
SELECT * FROM %SQL_Manager.Partitions('demo','log');
```

:information_source: this catalog query is for internal use. A public view in `INFORMATION_SCHEMA` is forthcoming.

This query should return 2 rows, one for the current month and one for those two future records (as per the `DATEADD()` function call), with the location where the partitions are stored. As you'll see, they're still both in the USER database, which is the default for this namespace. This is because thus far, we've only specified _how_ the table data should be partitioned, and not _where_ to map it to. This is achieved through a tool called the *Extent Mapper*.

### The Extent Mapper

The Extent Mapper helps you map partitions to databases other than the default one for a given namespace, and comes with a set of straightforward SQL commands. With the following command, we'll map all data for partitions covering 2023 to the `data-2023` database, and data for partitions earlier than that to the `archive` database:
```SQL
ALTER TABLE demo.log MOVE PARTITION BETWEEN '2023-01-01' AND '2023-12-31' TO "data-2023";
ALTER TABLE demo.log MOVE PARTITION BETWEEN '2000-01-01' AND '2022-12-31' TO "archive";
```

In the above command, the `BETWEEN` keyword is used to specify a date range, because the partition key for our table is using range partitioning. The values we specified are used to identify the first and last partition to move. Please refer to the documentation for more on the specific syntax for other partition schemes.

When working from the catalog query we used before, you can also specify the partition IDs directly, using individual values or a range (when using range partitioning):
```SQL
ALTER TABLE demo.log MOVE PARTITION ID '202401000000' TO "data-2024";
ALTER TABLE demo.log MOVE PARTITION ID BETWEEN '202401000000' AND '202412000000' TO "data-2024";
```

If you consult the catalog query we used earlier again, you won't quite see anything, because a partition only exists when there's actual data in it. A separate catalog query exists to show the current mappings themselves:
```SQL
SELECT * FROM %SQL_Manager.PartitionMappings('demo','log');
```

Now let's add some data for these periods, and verify the data went into the right database:
```SQL
INSERT INTO demo.log (log_ts, log_level, message) VALUES ('2014-02-27', 'INFO', 'this happened over a decade ago!');
INSERT INTO demo.log (log_ts, log_level, message) VALUES ('2023-01-01', 'INFO', 'Happy 2023!!');
INSERT INTO demo.log (log_ts, log_level, message) VALUES ('2024-12-25', 'INFO', 'Merry Christmas!!');

SELECT * FROM %SQL_Manager.Partitions('demo','log');
```
You should now see how the records (partitions) ended up in the right database. As we haven't specified a mapping for the 2025 data, those records continue to go into the namespace's default database, though nothing prevents us from specifying a mapping for current or future records upfront.

:warning: Currently, moving nonempty partitions is not supported. This will be available shortly.

### Under the hood

TBC


## Frequently Asked Questions

### Who needs Table Partitioning?

Most applications or schemas where data accumulates over time (or starts off big!) will benefit from adopting Table Partitioning. It is especially relevant to customers who are concerned about the cost of hosting their whole database on premium storage, just because a slice of that database is "hot data" that needs to be available at the ultra-low latency offered by that premium storage tier.

### Does this offer fully automatic storage tiering?

The Table Partitioning capability described here will start off as a platform feature and offers the tools for an administrator to define an information lifecycle policy that includes moving data between storage tiers and archiving old partitions, but does not magically automate this process. Such automation requires more knowledge about the environment, not least about the available storage tiers and overall intent. Our cloud services, where we control that environment, are better positioned to (and will) deliver that kind of automation layer on top of the platform-level feature.

### When will this feature be available with InterSystems IRIS?

You can try the new capability through the [Early Access Program](https://www.intersystems.com/early-access-program/) now, and we hope to include it in an IRIS release later in 2025.

### How does it work?

At a technical level, Table Partitioning relies on additional leading subscripts that encode the partition key value, used universally for row data, indices, and other associated data structures. At schema design time, users can pick a partition key such as a date field or region, and how that field's values should translate to partitions, such as monthly date ranges, or a single partition per region. When rows are added to a partitioned table, the SQL (or Object) Filer will calculate the proper subscript values for each row and make sure data ends up in the right place. Using a new tool called the Extent Mapper (available through simple DDL commands), users can then map or move partitions from one database to another using logical criteria, such as moving all the partitions for 2021 to one database and those for 2022 to another. 

### Couldn't I do this already with subscript-level mappings?

To some extent, yes. In fact, Table Partitioning relies on subscript-level mappings to wire data to the right place, but the big difference is that it introduces those additional subscripts the mappings are based on and allows you to express the mapping in logical terms, relevant to what you defined as a partition scheme. Prior to this, users could only manually create mappings based on the RowID, which has no logical meaning beyond a wild approximation of record age, and had no way whatsoever to meaningfully split index globals.

### Can I convert my existing tables to use partitioning?

Yes, we're including `ALTER TABLE .. CONVERT ..` syntax to allow transforming an existing table into a partitioned table and vice versa. This command is not part of the initial release though. Also note that some conversions imply a change to the RowID and may require updates to tables with a foreign key constraint pointing to the table being converted.

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

## How to get help?

Please use the [Issues](issues) section in this repository if you have questions about the tutorial, or ask your questions on the [Developer Community](htttps://community.intersystems.com/)