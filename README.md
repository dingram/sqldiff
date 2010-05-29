Introduction
============

A perl utility for scanning two MySQL database schemas and generating a diff
between them. The result will be the necessary SQL for transforming the first
database schema into the second.

The script will also make judgements about the relative safety of the
operations.

## Safe Operations ##

 - Adding a table
 - Adding a column
 - Column type change that would cause no data loss (e.g. `INT` -> `BIGINT`,
   `UINT` -> `INT`, `VARCHAR` -> `TEXT`, `INT` -> `VARCHAR`, `INT` ->
   `FLOAT`, ...)
 - Changing `NOT NULL` to `NULL`
 - Adding an `UNIQUE`, `FULLTEXT`, or standard `INDEX` to a column

## Unsafe Operations ##

 - Removing a table
 - Changing table storage engine
 - Changing character set/collation
 - Column removal
 - Column rename
 - Addition/removal of `auto_increment` on a column
 - Changing `NULL` to `NOT NULL`
 - Changing primary key
 - Changing default value
 - Column type change that may lose data
 - Index removal
   - **NOTE:** `DEFAULT CURRENT_TIMESTAMP`, `ON UPDATE CURRENT_TIMESTAMP`, and
     `auto_increment` columns must be indexed. Beware multi-column indexes.

## Ignored Operations ##

 - Change of index type (`BTREE`/`RTREE`/`HASH`)
 - Change of table `AUTO_INCREMENT` value

Upcoming features
=================

 - Allow database schemas to be read from database hosts directly rather than
   from dump files.
 - Interpret statements other than USE/CREATE DATABASE/CREATE TABLE/DROP TABLE
 - Detecting "safe" character set/collation changes
 - Detecting "safe" shrinking of column type
 - Combine SQL deltas to form a single delta
 - Combine 1+ deltas with a base schema to form an updated base schema
