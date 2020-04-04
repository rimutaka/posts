# Cloud migration assessment with Microsoft DMA and SqlPackage tools

#### A short guide for anyone tasked with assessing migration to Azure SQL for the first time

![Intro](intro.png)

---

In theory, Azure SQL is a cloud version of MS SQL server. In practice, there are numerous limitations and incompatibilities with MS SQL we are used to running on our own servers.

The quickest and easiest way of assessing the compatibility your MS SQL DB with Azure SQL is to use [Database Migration Assistant](https://docs.microsoft.com/en-us/sql/dma/dma-overview) (DMA). It can connect to your database and produces a detailed report within minutes.

![dma-feature-parity.png](dma-feature-parity.png)

It is good at providing an overview of compatibility issues, but the UI doesn't make it easy to look deeper into details of individual issues and the only other viewing option is a JSON report file that is not easy to parse either.

![DMA Report](dma-report-1.png)

## Using sqlpackage.exe as a DMA alternative

*SqlPackage* is a command-line utility to get a different view of the compatibility issues - [SQL Package Utility](https://docs.microsoft.com/en-us/sql/tools/sqlpackage). Its main purpose is to export MS SQL databases into `bacpac` format for importing into Azure SQL, but its error report can be used for migration insight as well.

The utility was written in .net and can be run on Win, Mac and Linux platforms with just one line:

`sqlpackage.exe /Action:Export /ssn:127.0.0.1 /su:sa /sp:sapwd /sdn:test_db /tf:test_db.bacpac`

At first glance, the output of *sqlpackage.exe* may look gibberish. There were definitely some compatibility issues in this example, but the format of the output was not any more useful than with *DMA tool*.

![sql-package-red-report.png](sql-package-red-report.png)

Viewing the output in *Notepad++* makes it a bit clearer, but not clear enough to make sense of it. In my case, I stood little chance of me getting any useful info from 25,000 lines of very dense verbiage.

![notepad++](25000-errors.png)

### Prettifying the output

Unfortunately, *SQL Package tool* has a problem with large error reports. They come out with broken lines and are hard to parse. There is a simple way to tidy them up in *Notepad++*:

1. Remove the summary info at the top and bottom of the file.
2. Replace all new lines with a single space.
3. Replace `Error SQL` with `\nError SQL` in *extended* find-and-replace mode.

Your document should have one error message per line after the replacement. For example, my 25,000 lines shrunk to "just" 11,673 lines of very repetitive error messages, so the next logical step would be to find some patterns.

![img](sqlpackage-formatting.png)

### Resolving incompatibility issues

My key questions for estimating the extent of incompatibilities were:
1. How many tables, views, procedures and other objects are affected?
2. What are the common issues?
3. Can they be fixed by automatically refactoring the code?

Applying this regex `Error[^\[]*(\[[^\]]+\]\.\[[^\]]+\])` to the error report converted long verbose messages like

```
Error SQL71561: Error validating element [dbo].[tbt_estimatedCategory].[label]: Computed Column: [dbo].[tbt_estimatedCategory].[label] has an unresolved reference to object [CITI_CENTRAL].[dbo].[tbt_estimatedCategory].[label]. External references are not supported when creating a package from this platform.
```

into a relatively clean list of affected object names

```
[dbo].[VW_RENTRESERVATION_CALENDAR]
[dbo].[VW_RENTRESERVATION_CALENDAR]
[dbo].[tbt_estimatedCategory]
[dbo].[tbt_estimatedCategory]
[dbo].[tbt_estimatedCategory]
[dbo].[tbt_estimatedCategory]
[dbo].[tbt_estimatedCategory]
[dbo].[tbt_estimatedCategory]
[dbo].[VW_RENTRESERVATION_CALENDAR_NL]
```

which can be further de-duped to a unique list of object names that need attention

```
VW_RENTRESERVATION_CALENDAR
tbt_estimatedCategory
VW_RENTRESERVATION_CALENDAR_NL
```

That answers our first question: *What objects are affected?*

### Finding patterns

I used a very unscientific method of scrolling up and down the report and running some keyword searches trying to quantify common issues. A clear pattern of top problems emerged within a few minutes:

* cross-DB references
* references to non-existent table columns from view definitions
* references to other non-existent objects like functions and SPs

The references to **non-existent columns and functions** may sound strange, but there is a high chance that schema changes have accumulated over the lifetime of the system. MS SQL allows objects to be dropped without checking their dependents, unless [WITH SCHEMA BINDING](https://www.mssqltips.com/sqlservertip/4673/benefits-of-schemabinding-in-sql-server/) option was specified. 

Identifying objects with broken references is actually good news. If we know that a certain object has been broken in production for a long time and no one complained it is probably no longer used and can be marked for deletion.

**Partitioning the report into different types of migration problems will give you the numbers needed to come up with an early migration cost estimate.**

### Estimation multiplier

500 identical code changes can be done in 15 minutes with global search-and-replace. A small number of unique issues may take days of work. Remember to include testing, staging and making changes to DevOps. I suggest to [quadruple the initial estimate](https://en.wikipedia.org/wiki/Pareto_principle) to account for that.

----

## Data Migration Assistant vs. SQL Package comparison

In short, both tools are complimentary of each other and I recommend using both.

### DMA
* more issue types covered
* recommendations
* summary per type of issue
* detailed info is hard to extract
* many of the problems are just "warnings" and do not affect the migration as such
* [doesn't work with the latest MS SQL (2019)](https://social.msdn.microsoft.com/Forums/sqlserver/en-US/6a4a6106-7335-4e39-aa56-65c20c90df53/upgrade-advisory-report-failure-on-sql-server-2019) as the source

  #### Watch out for deprecated data types 

  DMA puts deprecated data types like `text`, `ntext` and `image` into *warnings* section. You can still migrate those to AZ as-is, but expect some of the code to fail where those types are involved. We had to completely eliminate them from all our parameters in functions and procedures. *Text* became *nvarchar(max)* and *image* became *varbinary(max)*.

### SqlPackage

* lists only inconsistencies in the schema and code that prevent it from exporting the DB
* the output is easier to parse than the JSON report from DMA
* no recommendations are included in the report
* not concerned with the quality of the code
* not concerned with issues that will arise after the migration
