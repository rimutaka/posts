# Migration of Cross-DB Queries and Linked Servers from on-prem MS SQL to Azure ElasticQuery
#### A practical guide for migrating SELECT, INSERT, UPDATE, DELETE and EXEC statements to ElasticQuery at scale

This guide is based on experience gained during migration of a real-estate management system with hundreds of MS SQL databases from on-prem to Azure. It focuses on cross-database queries which became the major issue for the migration due to limitations of Azure SQL and Azure ElasticQuery.

Consider this on-prem cross-DB query as an example:

```sql
select  *  from srv_sql2008.central.dbo.tb_agency where code_version = @ver
```
The FROM clause of the above query contains a standard [multipart table name](https://docs.microsoft.com/en-us/sql/t-sql/language-elements/transact-sql-syntax-conventions-transact-sql#multipart-names):
* linked server name: `srv_sql2008`
* remote database name: `central`
* owner + table name: `dbo.tb_agency`

Running the same query on Azure SQL will return an error: 
```
Msg 40515, Level 15, State 1, Line 16
Reference to database and/or server name in 'srv_sql2008.central.dbo.tb_agency' is not supported in this version of SQL Server.
```

The problem here is that Azure SQL [Elastic Query](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-elastic-query-overview) framework for accessing data between databases differs from [Linked Server / DTC](https://docs.microsoft.com/en-us/sql/relational-databases/linked-servers/linked-servers-database-engine) concept used by MS SQL Server creating incompatibility between the two platforms. 

To get around this problem, SELECT statements can be refactored to use [External Tables](https://docs.microsoft.com/en-us/sql/t-sql/statements/create-external-table-transact-sql), but the biggest limitation is that **Elastic Query does not support DML operations like INSERT, UPDATE or DELETE**. That limitation is a major impediment for most on-prem multi-database systems trying to migrate to Azure.

*It is puzzling why Microsofts has not implemented such an important and commonly used feature of MS SQL in Azure. Their suggested workaround is to use a remote procedure call, which doesn't fully address the problem. Migrating a system with hundreds or thousands of cross-database INSERT / UPDATE / DELETE statements that have to be converted into remote SP calls is a costly undertaking.*

#### To solve this problem, we implemented a solution that allowed us to minimize the cost of migration by automating the code refactoring in views, functions and stored procedures that complies with Azure ElasticQuery limitations.

---

# Mirror-table alternative for using INSERT/UPDATE/DELETE with ElasticQuery 

The core idea is to create mirror objects for tables and stored procedures to make DML (INSERT/UPDATE/DELETE) operations appear local and abstract the remote part of the interaction.

![intro](intro.png)

#### Terminology

* `Table_A` - a table in DB2 we want to insert data into from DB1
* `mirror table` - a table with the same definition as the table it is mirroring

#### Explanation

The 3 or 4 part table names like `DB2..Table_A` won't work on Azure. We create a mirror of *Table_A* in *DB1* and perform local INSERTs into it instead of the remote table. Then we invoke an SP in *DB2* to let it know there is new data in the mirror table. The remote SP in *DB2* reads the new data from the mirror table in *DB1* via an external table and inserts it into *Table_A*, which is the intended destination for the data.

![intro with sp calls](intro-with-sp-calls.png)

**The main advantage** of this method is the ease of refactoring the existing T-SQL codebase:
1. mirror tables, external tables and both SPs can be auto-generated
2. the 3 and 4-part names in INSERT, DELETE and UPDATE statements can be changed using global search and replace
3. the more lines of T-SQL code you need to change the more time this approach saves you

The **disadvantages** are:

1. a large number of tables and SPs are added to the DB schema
2. slower DML performance

## Practical example

We will create two test databases in Azure SQL (`test_master` and `test_mirror`) and insert data from *test_mirror* into *test_master* using a mirror table.

#### Tables

We'll need an equivalent of `Table_A` from the diagram above in `test_master` database. Let's call it `tb_a` for brevity. Our goal is to insert data into `tb_a` in `test_master` from an SQL statement in `test_mirror`.

```sql
-- USE test_master
DROP TABLE IF EXISTS [dbo].[tb_a]

CREATE TABLE [dbo].[tb_a](
	[key] [int] NULL,
	[value] [nvarchar](255) NULL,
	mirror_key uniqueidentifier NULL
) ON [PRIMARY]
```

Table `mr_tb_a` is the exact copy of `tb_a`.

```sql
-- USE test_mirror
DROP TABLE IF EXISTS [dbo].[mr_tb_a]

CREATE TABLE [dbo].[mr_tb_a](
	[key] [int] NULL,
	[value] [nvarchar](255) NULL,
	mirror_key uniqueidentifier NULL
) ON [PRIMARY]
```

Table `ext_mr_tb_a` is an external table to access `mr_tb_a` from `test_master` DB. It has exactly the same definition as `mr_tb_a` and `tb_a`. You need to create `TestMirrorSrc` [external data source](https://docs.microsoft.com/en-us/sql/t-sql/statements/create-external-data-source-transact-sql) for this statement to work. 

```sql
-- USE test_master
CREATE EXTERNAL TABLE ext_mr_tb_a (
	[key] [int] NULL,
	[value] [nvarchar](255) NULL,
	mirror_key uniqueidentifier NULL
)
WITH ( DATA_SOURCE = TestMirrorSrc, SCHEMA_NAME = N'dbo', OBJECT_NAME = N'mr_tb_a' )
```

#### Stored Procedures

An SP from `test_mirror` calls an SP on `test_master` with a value for `mirror_key` field for new records. It is not possible to pass a recordset with ElasticQuery remote procedure call (only scalar types are allowed), so we'll mark multiple records with a unique ID and pass it as a single parameter.

```sql
-- USE test_master
DROP PROCEDURE IF EXISTS sp_InsertFromRemoteMirror
GO

CREATE PROCEDURE sp_InsertFromRemoteMirror
(@mirror_key AS UNIQUEIDENTIFIER)
AS
BEGIN
    insert into tb_a select * from ext_mr_tb_a where mirror_key = @mirror_key 
END
```

The following SP calls `sp_InsertFromRemoteMirror` when new data is inserted into `mr_tb_a` on `test_mirror`.

```sql
-- USE test_mirror
DROP PROCEDURE IF EXISTS sp_InsertIntoRemoteMaster
GO

CREATE PROCEDURE sp_InsertIntoRemoteMaster
AS
BEGIN

	declare @mirror_key_local AS UNIQUEIDENTIFIER
	set @mirror_key_local = NEWID()

	update mr_tb_a set mirror_key = @mirror_key_local where mirror_key is null

   	exec sp_execute_remote @data_source_name  = N'TestMasterSrc', 
		@stmt = N'sp_InsertFromRemoteMirror @mirror_key', 
		@params = N'@mirror_key AS UNIQUEIDENTIFIER',
		@mirror_key = @mirror_key_local; 

	delete from mr_tb_a where mirror_key = @mirror_key_local

END
```

The DELETE statement at the end of `sp_InsertFromRemoteMirror` is optional to keep the mirror table small. It can be removed to maintain the full mirror of the remote data for tracking updates and deletes. Consider adding indexes to `mr_tb_a` if you want to retain the entire set of records.

The code examples presented above may be hard to follow. This diagram should help you understand how everything fits together.

![intro diagram with object names](intro-with-sp-calls-labeled.png)

#### Test DML statement

Before migrating to Azure SQL (on-prem):
```sql
USE test_mirror
insert into test_master.dbo.tb_a ([key],[value]) values (10,'x')
```

Refactored code for ElasticQuery on Azure SQL:
```sql
-- USE test_mirror
insert into mr_tb_a ([key],[value]) values (10,'x')
exec sp_InsertIntoRemoteMaster
```

### UPDATE and DELETE statements

The example above demonstrates how to use mirror tables to modify INSERT statements for ElasticQuery. A similar approach can be used with cross-DB UPDATE and DELETE statements.

### EXEC statements

Refactoring remote procedure calls can be done by creating local proxy SPs and changing only object names in the existing code.

Before migrating to Azure SQL:
```sql
exec PBL_Location.dbo.sp_RemoveObjectLocation @ObjectLocationId, @ChannelId
```

Refactored code for ElasticQuery on Azure SQL:
```sql
exec ext__PBL_Location__sp_RemoveObjectLocation @ObjectLocationId, @ChannelId
```

via a local proxy SP
```sql
CREATE PROCEDURE ext__PBL_Location__sp_RemoveObjectLocation
@p_Id_ObjectLocation numeric(18,0),@p_Id_Channel numeric(18,0)
AS
    exec sp_execute_remote @data_source_name  = N'RemoteDB_pbl_location', 
		@stmt = N'exec sp_RemoveObjectLocation (@p_Id_ObjectLocation,@p_Id_Channel)', 
		@params = N'@p_Id_ObjectLocation numeric(18,0),@p_Id_Channel numeric(18,0)'
		,
@p_Id_ObjectLocation=@p_Id_ObjectLocation,@p_Id_Channel=@p_Id_Channel; 
```

The main advantages of this approach are:
* minimal changes to the existing code
* auto-generation of proxy SP code

# Automated T-SQL code refactoring for ElasticQuery

*This section is a summary of our code refactoring process. We used specialized tools and techniques to shortcut the development cycle and reduce the cost of migration. It may be of value to DBAs and other technical personnel migrating large number of databases to Azure SQL.*

Popular tools like [RedGate](https://www.red-gate.com/products/sql-development/sql-prompt/) and [Apex](https://www.apexsql.com/sql-tools-refactor.aspx) offer code refactoring, but what we needed for this task was too specific. We built a C# CLI utility (AZPM) to automate the process. You can find the source code under https://github.com/rimutaka/onprem2az-elastic-query

#### Refactoring steps

1. Identify all statements that need refactoring
2. Prepare code templates and config files for AZPM utility
3. Generate mirror and proxy objects with AZPM CLI
4. Change object names throughout the entire codebase, manually or with AZMP CLI
5. Export to Azure

#### A note on testing

Testing SQL code after making manual changes would be very expensive. In our project, we had nothing in terms of a test harness or even understanding what some of the code does. Some SPs ran into hundreds of lines of T-SQL code with very intricate business logic. It wouldn't take much to break that.

**Our goal was to devise a robust refactoring process** that can be tested on a small subset of code and then applied to the entire codebase with minimal risk of regression.

## Step 1: *code analysis*

The target for our search was multipart object names in SQL statements. We used two different search methods:

1. Looking for dependencies in system tables. E.g. https://www.red-gate.com/simple-talk/blogs/discovering-three-or-four-part-names-in-sql-server-database-code/
2. Using Regex to search through the source code. 

Regex (2) was the primary method and the system table search (1) was a backup for validation of Regex results.

Our very first step was to script all DB objects from all databases and add them to Git. 

**Suitable scripting tools**:
* SSMS *Script DB objects* feature via [MS Docs](https://docs.microsoft.com/en-us/sql/ssms/tutorials/scripting-ssms)
* PowerShell/T-SQL via [MSSQL Tips](https://www.mssqltips.com/sqlservertip/4606/generate-tsql-scripts-for-all-sql-server-databases-and-all-objects-using-powershell/)
* SchemaZen via [Github](https://github.com/sethreno/schemazen) / C#
* MSSQL Scripter via [Github](https://github.com/Microsoft/mssql-scripter) / Python
* DB Diff via [Github](https://github.com/OpenDBDiff/OpenDBDiff) / C#

#### Important considerations for scripting

1. **Consistency** - all scripts must follow the same pattern to produce meaningful diffs.
2. **Idempotency** - generate DROP with IF EXISTS for every CREATE to re-run the scripts as many times as needed.
3. **No** "*USE [db name]*" - it is [not supported by AZ SQL](https://docs.microsoft.com/en-us/sql/t-sql/language-elements/use-transact-sql) and will get in the way if you need to re-create objects there.
4. **Minimalism** - generate scripts only for what you need. Any extra code or comments will get in the way.
5. **One file per DB object** - the granularity level required to produce meaningful diffs. 

We committed the very first output of the script generator to Git, one database per repo. After that, we combined all scripts under a single SSMS solution, one project per DB. That gave us the full power of SSMS UI with tracking of all code changes in Git.

#### Search strategies

There is probably no single winning strategy for finding multipart names because of the myriad of ways the T-SQL code can be written. We started our search in SSMS to at least get some understanding of the codebase. It was an easy way to search for keywords and look up the affected code. Once we knew what exactly we were looking for we started using GREP to output the search results in a structured form.

**Sample GREP query**
```bash
grep -i -r -n --include '*.sql'  -E '\binsert\s*into\s*\[?CITI_\w+\]?\.\[?\w*\]?\.\[?\w*\]?' . > cross-db-insert-grep.txt
```
Our search was aided by a simple naming convention that all DB names were starting with prefix `CITI_`. You will encounter that prefix in most of our examples. Modify our Regex to match your naming convention, if such exists.

**Sample GREP output** 
```
./citi_4vallees/dbo.sp_AddChannelInPBL.StoredProcedure.sql:28:	INSERT INTO CITI_PBLCITI.dbo.TBR_CHANNEL_AGENCY
./citi_4vallees/dbo.sp_AddChannelInPBL.StoredProcedure.sql:110:	INSERT INTO CITI_PBLCITI.dbo.TBR_CHANNEL_AGENCY
./citi_4vallees/dbo.sp_getPrestationForPPE.StoredProcedure.sql:129:INSERT INTO citi_reporting_PPE.[dbo].[TB_VIEW_PPE_BILAN]
./citi_4vallees/dbo.sp_InsertPastaLight.StoredProcedure.sql:20:INSERT INTO CITI_STATS..TB_PastaLightData
```

Every line of the output contains:
* source DB name (e.g. *citi_4vallees*)
* procedure name (e.g. *sp_AddChannelInPBL*)
* the exact line number where the change to the object name must be made (e.g. *:28:*)

The GREP output was used as input into AZPM utility to change object names from a 4-part-name to the name of its mirror table or the proxy SP. We reviewed all GREP files before feeding them into AZPM utility to remove lines that didn't need to be modified or modified them by hand if they fell outside the normal pattern. It was a more robust way of doing global renaming than running a blind search-and-replace.

#### Search variations

T-SQL queries can vary syntactically, while being semantically equivalent. We encountered the following variations in our code:

* INSERT vs INSERT INTO
* EXEC vs EXECUTE
* optional schema name, e.g. DB_Name..sp_DoSomething vs. DB_Name.dbo.sp_DoSomething
* optional use of square brackets, e.g. `[name]` vs. `name`
* commented-out lines

We also encountered some **dynamic SQL** ... 

```sql
SET @Query = 'update [' + @dbName + '].dbo.[tb_Rent] SET RO_CONFIRMEDCATEGORY = 0 WHERE ConfDate < ''' + @ValidDate + ''''
EXEC (@Query)
```

Dynamic SQL queries can be extremely hard to find. Look for *EXEC* and *EXECUTE* statements and what precedes them.

#### Regex queries
These are a few examples of Regex queries we used on our GREP output to clean it up.

* Files ending in 'Database.sql': `^.*\.Database\.sql:.*$` 
* Lines with SPs: `^[^:]*:\d*:.*(\[?(\bCITI_\w*)\]?\.\[?(\w*)\]?\.(\[?\w*\]?))\s*\(`
* Same-DB references (multipart names that can be simplified to a 1-part name): `^\.\/([\w\d]+)\/.*(\[?\b\1\]?\..*)`
* Various name parts as groups: `^\.\/(\w*).*(\[?(\bCITI_\w*)\]?\.\[?(\w*)\]?\.(\[?\w*\]?))` and `^(\.\/([^\/]*)[^:]*):(\d*):(.*)$`
* Empty lines: `^\.\/[^\/]*[^:]*:\d*:\s*$`
* Commented-out lines: `^[^:]*:\d*:\s*--.*`
* Table names for config files: `^\.\/(\w*).*(\[?(\bCITI_\w*)\]?\.\[?(\w*)\]?\.(\[?\w*\]?))`

*I am infinitely grateful for the existence of https://regexr.com and highly recommend it for your Regex experimentation.*

#### Unused SQL code

There was a good part of the codebase that was no longer in use. Removing unused tables, views, functions and procedures saved us a lot of pain later in the process.

Dropping unused objects is risky. It may take a while to trace application errors to missing objects if they were dropped by mistake. Instead of dropping them we replaced the body of Stored Procedures with an error message:
```sql
THROW 51000, 'Removed for Azure SQL compatibility. See Jira issues for details.', 1;
```
and with an error-generating statement in User Defined Functions (can't use *THROW* in those):
```sql
BEGIN
		declare @x int
		set @x = cast('Removed for Azure SQL compatibility. See Jira issues for details.' as int);
		return null
END
```
We also set up an alarm in Azure Monitor to look for those error messages in the log stream to catch them quickly.

#### Conclusion of code analysis

Our code analysis stage "ended" only when all our databases were successfully imported into Azure SQL. We had to come back to fix the grep output, re-run the global replace and re-create SQL objects again and again until all the issues were resolved. It was very important to keep the process *idempotent* and fully scripted to achieve that.

## Steps 2-3: *generating mirror and proxy templates*

Our CLI utility (AZPM) generated all the proxy and mirror objects using config files and T-SQL templates. For example, to create an external table you have to include the full table definition with field names and their data types into the CREATE statement. AZPM completely automates the process by using templates and retrieving table definitions.

The following is an example of a template for generating an external table:

```sql
if exists(select 1 from sys.external_tables where [name] ='ext_{0}__{2}')
	begin
		DROP EXTERNAL TABLE ext_{0}__{2}
	end
	else
	begin
		DROP TABLE IF EXISTS ext_{0}__{2}
	end
GO

CREATE EXTERNAL TABLE ext_{0}__{2}(
	{3}
)WITH ( DATA_SOURCE = RemoteDB_{0}, SCHEMA_NAME = N'dbo', OBJECT_NAME = N'mr_{1}__{2}')
```
The utility would take the list of objects from a config file, connect to the DB in question, retrieve the table definition and replace `{0}`, `{1}` and other `{n}` placeholders with proper values.

This is an example of a config file from one of our databases:

![config file example](config.json.png)

A generated CREATE statement for table *ext_4VALLEES__tbc_estimatedcategory* may look like this:

```sql
if exists(select 1 from sys.external_tables where [name] ='ext_4VALLEES__tbc_estimatedcategory')
	begin
		DROP EXTERNAL TABLE ext_4VALLEES__tbc_estimatedcategory
	end
	else
	begin
		DROP TABLE IF EXISTS ext_4VALLEES__tbc_estimatedcategory
	end
GO

CREATE EXTERNAL TABLE ext_4VALLEES__tbc_estimatedcategory(
[ID_ESTIMATEDCATEGORY] numeric(18,0) NULL,
[LABEL] varchar(255) NULL,
[DTCREATION] datetime NULL,
[DTLASTUPDATE] datetime NULL,
[mirror_key] uniqueidentifier NULL
)WITH ( DATA_SOURCE = RemoteDB_4VALLEES, SCHEMA_NAME = N'dbo', OBJECT_NAME = N'mr_central__tbc_estimatedcategory')
```

Both, templates and config files can be modified to suit the specifics of your project.

AZPM utility also creates PowerShell scripts for applying the auto-generated SQL scripts and adding them to the repo on success:

```powershell
sqlcmd -b -S "pu6tt2a.database.windows.net" -U 'sa-pu6tt2a' -d central -i "CreateExtTable__central__4VALLEES__tbc_EstimatedCategory.sql"
if ($LASTEXITCODE -eq 0) {git add "CreateExtTable__central__4VALLEES__tbc_EstimatedCategory.sql"}
```

#### Summary of the code search and generation process

1. Run a GREP query to extract 4-part names in a particular context, e.g. for INSERTs.
2. Extract object names from the GREP results and put them into config files.
3. Generate mirror and proxy objects.
4. Add the objects to their respective DBs.
5. Review and commit the changes.

The process proved to be robust and consistent to be run again and again, in part or in full until we resolved all incompatibility issues.

## Step 4: *global replace*

By this time in the process, we had all necessary mirror and proxy objects generated and applied by AZPM utility. The actual replacing of the names was also [fully automated](https://github.com/rimutaka/onprem2az-elastic-query#replace) using a single command line in PowerShell.

```powershell
azpm.exe replace -t ext_{1}__{2} -g C:\migration-repo\cross-db-exec-grep-4v.txt
```
where `ext_{1}__{2}` is the renaming template and `cross-db-exec-grep-4v.txt` is a sanitised GREP output file from the previous step.

AZPM utility goes through every line in the GREP output file and modifies the original names in the referenced *.sql* file according to the template, like in this example:
```sql
exec PBL_Location.dbo.sp_RemoveObjectLocation @ObjectLocationId, @ChannelId
exec ext__PBL_Location__sp_RemoveObjectLocation @ObjectLocationId,@ChannelId
```

All modified *.sql* files can be applied using auto-generated PowerShell scripts similar to this one:

```powershell
sqlcmd -b -S "."  -d central -i "dbo.sp_InsertPasta.StoredProcedure.sql" 
if ($LASTEXITCODE -ne 0) {git reset "dbo.sp_InsertPasta.StoredProcedure.sql"}
```

## Step 5: *exporting for Azure SQL*

The [export process](https://docs.microsoft.com/en-us/sql/tools/sqlpackage#export-parameters-and-properties) is simple enough and fits into a single PowerShell line:
```powershell
sqlpackage.exe /Action:Export /ssn:127.0.0.1 /su:sa /sp:$pwd /sdn:$db /tf:$fileName #/d:True
```
Successfully exported *.bacpac* files can be uploaded to Azure SQL for testing.

We used a slightly longer script to export *.bacpac* files for multiple DBs at once.
```powershell
<# .DESCRIPTION
This script exports .bacpack files for importing into AZ SQL DB
The list of DBs is taken from `$dbs` variables specified in `vars.ps1`.
`.bacpack` files are exported into `./bacpac`k folder, but are not overwritten
Put your sql server `sa` account pwd into $env:SA_PWD or store it right inside this file
Use ` *>&1 | Tee-Object -FilePath bacpac\error-report-xxx.txt` for file/console output.
Run it from the root of the solution.
#>
. (Join-Path $PSScriptRoot vars.ps1)

# output folder
$folder = "bacpac"

# create the output forlder on the first run
if (!(Test-Path -Path $folder )) {
  New-Item -Path . -Name $folder -ItemType "directory" -Force
}

foreach ($db in $dbs) {

  #  SA password is taken from env var called `SA_PWD`
  $pwd = $env:SA_PWD
  $fileName = "$folder\$db.bacpac"

  # do not overwrite existing files
  if (Test-Path -Path $fileName) {
    Write-Host "`n$fileName exists.`n" -ForegroundColor Yellow
    continue
  }

  $_fileName = "$folder\_" + "$db.bacpac"
  # do not overwrite existing files
  if (Test-Path -Path $_fileName) {
    Write-Host "`n$_fileName exists.`n" -ForegroundColor Yellow
    continue
  }

  sqlpackage.exe /Action:Export /ssn:127.0.0.1 /su:sa /sp:$pwd /sdn:$db /tf:$fileName #/d:True
  # You may want to enable `/d:True` flag if the utility fails with no good explanation to why
}
```

There is a good chance you'll have to run this script quite a few times before all of the incompatibilities get resolved. Keep in mind that SqlPackage utility does not parse dynamic SQL. It may also miss other compatibility issues. Your DB may export successfully and then fail to work as expected. Use [Microsoft DMA tool](https://docs.microsoft.com/en-us/sql/dma/dma-overview) to check for other compatibility issues.

# Conclusion

The original estimate for the migration was close to a year of manual refactoring by a team of SQL programmers. Using mirror tables and proxy stored procedures cut the migration time to 6 weeks. The full automation of the process allowed us to retrace our steps and re-run the entire migration with a press of a button every time a new problem was uncovered. We would not be able to complete the migration so fast if it wasn't for that level of automation.

---

*This post is based on my recent experience migrating a real estate management system with hundreds of MS SQL databases from on-prem to Azure SQL. Read my other articles for more learnings from that project.*