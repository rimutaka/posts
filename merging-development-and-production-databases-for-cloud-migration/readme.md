# Merging development and production MS SQL databases for cloud migration
#### A practical guide for large-scale "on-prem" to Azure SQL migration projects

*It can take a long time to prepare a system for migration to a cloud environment. There is a chance that the production codebase has changed during that time. This post offers a simple solution for identifying and merging such changes. The post is very specific to Azure migration and is unlikely to be of interest in any other context.*

Our cloud migration project took 3 months from taking a snapshot of all production databases to making the code fully compatible with Azure SQL. In the meantime, the SQL code in production changed to keep up with customer requests and bug fixes. We decided to ignore the changes until the very end of migration to compared and merged the entire codebase in a single sweep. The decision was based on the [universal precaution approach](https://en.wikipedia.org/wiki/Universal_precautions) because there could also be any number of untracked changes.

This diagram illustrates the relationship between DB codebase and the Git repository as a timeline. 

![process diagram deployment](process-diagram-dep.png)

## Background

The system consisted of two types of MS SQL databases: *customer* and *shared* (central) databases.

Every customer had a separate DB with a standardized schema and identical (in theory) codebase. Every shared DB had a different schema and codebase. All databases were tightly interlinked via cross-DB SQL queries.

![cust vs shared](cust-vs-shared.png)

#### Customer databases

*Customer DBs* had data specific to a single customer, but shared the same codebase. In practice, there were minute differences in the codebase as well. E.g. customer-specific code and accumulation of Dev-Ops errors.

**Only the differences affecting AZ compatibility would have to be identified and merged.**

Naming conventions:

* `c_4vallees_base` - the original customer DB snapshot taken for development
* `c_4vallees_model` - *c_4vallees_base* modified for AZ
* `c_4vallees` - the latest copy from production
* `c_8hdke93`, `c_a83hdk2`, `c_hdj3ud5` - the latest production copies of other customer DBs

#### Shared databases

*Shared DBs* have schema and code that are specific to each DB. No code is shared between them.

* `central`, `helpdesk`, `reporting` - latest production copies
* `central_base`, `helpdesk_base`, `reporting_base` - original snapshots taken for development (before any AZ modifications)


## Merge sequence

We start with 3 sets of T-SQL code for each database:
* `base` - the original snapshot before AZ mods
* `model` - a modified snapshot that works on AZ
* `prod` - the latest copy from production

and compare them in this order

1. `base` to `model` to get the list of all Azure compatibility changes
2. `base` to `prod` to find out changed in production while we were busy modding `base` for Azure
3. merge `prod` and `model`

**The main advantage of using this method is that it can be re-run on a newer production set within minutes if the Azure deployment was delayed or rolled back.**

![high level merge](intro-2.png)


## Project structure
All scripts provided in this guide rely on the following file structure:

* `\` - root_solution_folder
  * `db` - contains folders with T-SQL code from *snapshot* DBs
    * `c_4vallees` - T-SQL code of *c_4vallees* DB, including its own GIT repo
    * `central` - same for *central* and other DBs
    * `helpdesk`
    * `reporting`
    * etc ...
  * `utils` - all sorts of shell and SQL scripts for code refactoring and automation
  * `staging-diff` - diff files for comparing *base* and *model* versions
  * `customer-dbs` - modified code for customer DBs, based on a single *customer model DB*

All SQL code was committed to Git repositories, one repo per shared DB and one repo for a sample customer DB (*c_4vallees*). The rest of customer databases were supposed to be identical to the sample.

## Step 1: *identifying Azure compatibility modifications*
This script diffs the latest version of modified (*model*) DBs against their original (*base*) state and outputs a list of SQL objects changed for migration. We will need this list to limit our search for changes in production to those objects only. Any other production changes will carry over to Azure as-is.

This script should be run from the solution root because it expects database repositories to be in `./db/db_name` folders.

**Required input vars**:
* `$diffDBs` - an array with DB names, e.g. `$diffDBs = @("central", "helpdesk", "reporting")`
* `$diffFolderName` - relative path to the output folder, e.g. `$diffFolderName = "staging-diff"`

**Output**: a collection of diff files, one per DB, e.g. *staging-diff/init-head-diff-db_name.txt*


```powershell
. (Join-Path $PSScriptRoot vars.ps1)

# prepare paths and variables
$rootDir = (Get-Item -Path ".\").FullName
$diffDir = Join-Path $rootDir $diffFolderName

# create a folder for diffs, if needed
if (!(Test-Path -Path $diffDir )) {
  New-Item -Path $rootDir -Name $diffFolderName -ItemType "directory" -Force | Out-Null
}
"Diff folder: $diffDir"

foreach ($dbName in $diffDBs) {
  "`nDB: $dbName"
  
  # try to checkout master branch
  $dbCodeFolder = Join-Path "db" $dbName
  git -C $dbCodeFolder checkout master --force
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Cannot checkout MASTER on $dbCodeFolder" -ForegroundColor DarkRed
    continue
  }

  # get the very first commit with the unmodified (base) code
  $allCommits = git -C $dbCodeFolder rev-list HEAD
  $initialCommit = $allCommits.split()[-1]
  "Initial commit: $initialCommit"

  # save the list of all modified files
  $diffFileName = Join-Path $diffDir "init-head-diff-$dbName.txt"
  if (!(Test-Path -Path $diffFileName )) {
    $modFiles = git -C $dbCodeFolder diff --name-only $initialCommit HEAD
    "Files in diff: " + $modFiles.split().length
    Set-Content -Path $diffFileName -Value $modFiles
  }
  else {
    Write-Host "Diff file already exist: $diffFileName" -ForegroundColor Yellow
  }
}
```

The contents of the output from the script above is a list of all the file names (objects) affected by Azure modifications, per DB. The file names conform to SSMS object scripting format: *owner.object.type.sql*, one file per object.

![sample diff output](sample-diff-output.png)

## Step 2: *identifying recent changes in PROD*

In this step, we compare the code directly between *base* and *prod* DBs using *sys.syscomments* tables to avoid exporting all objects from production DBs. The comparison is done by an [open source CLI tool(AZPM)](https://github.com/rimutaka/onprem2az-elastic-query) we had to build for this project.

This PowerShell script relies on the output from *Step 1* and should also be run from the solution root.

**Required input vars**:
* `$diffDBs` - an array with DB names, e.g. `$diffDBs = @("central", "helpdesk", "reporting")`
* `$diffFolderName` - relative path to the output folder, e.g. `$diffFolderName = "staging-diff"`
* `$azpm` - location of [AZ migration CLI tool](https://github.com/rimutaka/onprem2az-elastic-query), e.g. `$azpm = "C:\Temp\AzurePoolCrossDbGenerator.exe"`
* `$modelCustomerDB` - name of the `model` customer DB. It is required only if you are processing customer DBs from a single `model`.

**Output**: new Git repo branches with unstaged files

```powershell
. (Join-Path $PSScriptRoot vars.ps1)

# prepare paths and variables
$rootDir = (Get-Item -Path ".\").FullName
$diffDir = Join-Path $rootDir $diffFolderName
"Diff folder: $diffDir"

# check if the diff folder exists
if (!(Test-Path -Path $diffDir )) {
  Write-Host "Cannot access the diffs in $diffDir " -ForegroundColor Red
  Exit
}

foreach ($dbName in $diffDBs) {
  $dbBase = $dbName + "_base" # the original version of the DB used for development
  $dbCodeDir = Join-Path "db" $dbName # folder with the code repo
  $diffFileName = Join-Path $diffDir "init-head-diff-$dbName.txt"
  <# Uncomment this block if processing customer DBs to compare them to the same base
  $dbBase = $modelCustomerDB + "_base"
  $dbCodeDir = Join-Path "db" $modelCustomerDB
  $diffFileName = Join-Path $diffDir "init-head-diff-$modelCustomerDB.txt"
  #>

  "`nStaging DB: $dbName"
  "Base DB: $dbBase"
  "Code repo: $dbCodeDir"

  # get the list of modified files
    if (!(Test-Path -Path $diffFileName )) {
    Write-Host "Cannot access diff file: $diffFileName" -ForegroundColor Red
    continue
  }
  
  # try to checkout master branch
  git -C $dbCodeDir checkout master --force
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Cannot checkout MASTER on $dbCodeDir" -ForegroundColor Red
    exit
  }

  # get the initial commit
  $allCommits = git -C $dbCodeDir rev-list HEAD
  $initialCommit = $allCommits.split()[-1]
  "Initial commit on master: $initialCommit"

  # check out the very first commit into a new branch
  $branchName = $dbName +"-" + (Get-Date -Format "yyyyMMddHHmm")
  git -C $dbCodeDir checkout -B $branchName $initialCommit
  if ($LASTEXITCODE -ne 0) {
    "Failed to checkout $initialCommit as branch $branchName"
    continue
  }

  # extract changed files from the diff list into the DB folder
  $csl = "`"Persist Security Info=False;Integrated Security=SSPI;Initial Catalog=$dbName;Server=.`"" # staging DB (latest prod)
  $csb = "`"Persist Security Info=False;Integrated Security=SSPI;Initial Catalog=$dbBase;Server=.`"" # a DB with the original code (base)
  $wd = Join-Path $rootDir $dbCodeDir

  Start-Process -FilePath $azpm -ArgumentList @("extract", "-csl", $csl, "-csb", $csb, "-l", "$diffFileName") -NoNewWindow -Wait -WorkingDirectory $wd

  # multiple customer DBs are extracted into the same folder, so we need to stash the changes to keep them separate
  # the stashes would need to be popped manually for further editing
    $stashMsg = "staging"
    git -C $dbCodeDir stash push -m $stashMsg
    # run `git stash clear` to remove all stashes in the repo

}
```

#### Customer DBs vs Shared DBs

The data in our system was partitioned into a single-DB per customer and several shared DBs for reporting, lists of values and taxonimies. All *shared DBs* were compared to their `base`. It was a 1:1 relationship. We could create a GIT branch for every comparison in every repo and leave the changes *staged* for review.

*Customer DBs*, on the other hand, were all compared to the same sample DB called `4vallees_base`. To keep the Git repo clean we *stashed* the changes for every *customer DB* to *base* comparison before moving onto the next DB. *Stashing* allowed us to review the diffs before making a commit.

For example, comparing customer DB *c_hdj3ud5* to *base* creates stash *c_hdj3ud5-202002211117:staging*.

![Git branches](git-branches-git.png)

The screenshot above shows 3 branches named *DB + timestamp* with corresponding *stashes* to be reviewed and merged with the Azure-ready code.

## Step 3: merging `base` and `prod`

The purpose of this merge is to converge our `base` version with the latest PROD changes.

For example, the diff in the screenshot below telled us that *prod* had some columns added.

![First Diff](git-1st-diff.png)

After some "cherry-picking" we ended up with this version of accepted differences:

![Second diff](git-staged-diff.png)

The merged tree had 2 branches: `master` for the *model DB* and another one for *PROD*,

![Tree before merge](git-tree-before-merge.png)

followed by a merge with all Azure compatibility changes from `master`.

![Fully merged with AZ](git-tree-merged-1-branch.png)

This diff confirmed that our AZ compatibility changes were present: cross-DB queries were correctly merged with Azure modifications and the new column names from *PROD*.

![AZ changes diff](git-tree-merge-staged-changes.png)

We repeated the merge for the other customer DBs from stashes and kept all customer-specific changes within their branches.

![3 DBs, 3 branches](git-tree-merged-3-branches.png)

## Applying merged changes back to PROD DBs

The following script generates SQL files with the merged code for all shared and customer DBs. The scripts can then be applied to PROD databases. 

Run the script from the solution root.

**Required input vars**:
* `$dbCustomers` - an array with DB names, e.g. `$dbCustomers = @("c_8hdke93", "c_a83hdk2", "c_hdj3ud5")`
* `$modelCustomerDB` - name of the *model* customer DB, e.g. `$modelCustomerDB = "4vallees"`
* Copy the diff for customer *model* DB to `customer_dbs\diff.txt` and make changes to the list inside, if needed
* This version of the script assumes that the SQL code modified for Azure is identical between all customer DBs. There may still be differences in other parts of customer databases, but what changed for Azure is identical.

**Output**: scripts for all modified objects are saved in `.\customer_dbs\db_name` folders.

```powershell
. (Join-Path $PSScriptRoot vars.ps1)

# source folder name - using the model DB
$sd = "db\" + $modelCustomerDB

# get the list of modified files from a diff
$diffFile = "customer-dbs\diff.txt"
if (!(Test-Path -Path $diffFile )) { 
  Write-Host "Missing the list of files to export: $diffFile" -ForegroundColor Red
  Exit
}

$diffFiles = (Get-Content $diffFile)

# remove all target DB scripts from the previous run
Write-Host "Deleting all SQL files in the target location ..." -ForegroundColor Yellow
foreach ($db in $dbCustomers) {
  $dbPath = "customer-dbs\" + $db
  if (Test-Path -Path $dbPath ) { Remove-Item -Path $dbPath -Force -Recurse }
}

$firstRun = 1 # reset to 0 after the first DB to reduce console output

foreach ($db in $dbCustomers) {

  Write-Host "$db" -ForegroundColor Yellow

  # target folder name - using the customer DB name
  $td = "customer-dbs\" + $db

  # process all SQL files from the diff
  foreach ($sqlFile in $diffFiles.Split("`n")) {

    if (! ($sqlFile -match ".+\.sql$")) {
      # report skipped files on the first run only
      if ($firstRun -eq 1) { Write-Host "Skipped $sqlFile" -ForegroundColor Yellow }
      continue
    }

    # check if the source file exists
    $sqlSourceFileName = Join-Path $sd $sqlFile
    if (!(Test-Path -Path $sqlSourceFileName )) { 
      if ($firstRun -eq 1) { Write-Host "Missing $sqlFile" -ForegroundColor Red } 
      continue
    }

    # replace model DB name with the target DB name
    $sqlTargetFileName = Join-Path $td $sqlFile

    # replace the contents of the file
    New-Item -Path $sqlTargetFileName -Force | Out-Null
    (Get-Content $sqlSourceFileName) | Foreach-Object { $_ -replace "$modelCustomerDB", "$db" } | Set-Content $sqlTargetFileName -Force
    # The () brackets around Get-Content are needed to make the file writable. Otherwise it would be locked.
  }

  # reset this flag to reduce console output
  $firstRun = 0
}
```

Running the above script for our 3 customer DBs produced ~ 600 SQL files.

![customer DB scripts](customer-db-scripts.png)

The following script applies the files generated in the previous step to production databases. Run it from the solution root.

**Required input vars**:
* `$dbCustomers` - an array with DB names, e.g. `$dbCustomers = @("c_8hdke93", "c_a83hdk2", "c_hdj3ud5")`
* `$customerDBsFolderName` - set to `$customerDBsFolderName = "customer-dbs"`.

**Output**: processed DB names and error messages from SQLCMD utility.

```powershell
. (Join-Path $PSScriptRoot vars.ps1)

foreach ($db in $dbCustomers) {
  Write-Host "$db" -ForegroundColor Yellow

  # folder name with DB files
  $td = Join-Path $customerDBsFolderName $db 
  if (!(Test-Path -Path $td )) {
    Write-Host "# Missing DB folder $db" -ForegroundColor Red
    continue
  }
  
  # get the list of files
  $allFiles = Get-ChildItem -Path $td -Filter "*.sql"
  foreach ($sqlFileName in $allFiles) {
    # file name as `customer-dbs\db_name\file_name.sql`
    $sqlFullFileName = (Join-Path $td $sqlFileName.Name)
    # run the SQL file on the local server, add -U and -P params if needed
    sqlcmd -b -S . -d $db -i `"$sqlFullFileName`"
    # output the file name for troubleshooting if there was a problem
    if ($LASTEXITCODE -ne 0) { $sqlFullFileName }
  }
}
```

The DBs are now ready for exporting into *bacpac* files required by AZ SQL DB import process. Run this script from the root of the solution to initiate the export.

**Required input vars**:
* `$dbs` - an array with DB names, e.g. `$dbs = @("c_8hdke93", "c_a83hdk2", "c_hdj3ud5")`
* Environmental var `SA_PWD` - enter your `sa` password in there.

**Output**: *.bacpac* files per DB in *bacpac* folder.

```powershell
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

  sqlpackage.exe /Action:Export /ssn:127.0.0.1 /su:sa /sp:$pwd /sdn:$db /tf:$fileName #/d:True
  # You may want to enable `/d:True` flag if the utility fails with no good explanation to why
}
```

There is a chance you will get some errors during the export. They will have to be addressed before the export can be completed. Sometimes it means going back to the very beginning and re-running the entire process again.

Successfully exported files can be imported into Azure SQL Pool with this PowerShell script.

**Required input vars**:
* `$dbs` - an array with DB names, e.g. `$dbs = @("c_8hdke93", "c_a83hdk2", "c_hdj3ud5")`
* Environmental var `SA_PWD` - enter your `sa` password for AZ SQL server / pool.
* `$AzUserName` - AZ SQL server admin user name, e.g. `$AzUserName = "sa"`
* `$AzResourceGroup`, `$AzServerName`, `$AzPoolName` - Azure SQL server params.

**Output**: list of *.bacpac* files names imported into AZ SQL.

```powershell
. (Join-Path $PSScriptRoot vars.ps1)

foreach ($db in $dbs) {
  #  SA password is taken from env var called `SA_PWD`
  $pwd = $env:SA_PWD
  $filename = "$db.bacpac"

  Write-Host "`n`nProcessing $fileName`n" -ForegroundColor Yellow

  # ignore if the file is not there
  if (!(Test-Path -Path $fileName)) {
    Write-Host "`n$fileName doesn't exist.`n" -ForegroundColor Red
    continue
  }

  # this line requires running `az login` and `az account set --subscription ...` first
  Write-Host "Deleting AZ SQL DB ..." -ForegroundColor Yellow
  az sql db delete --name $db --resource-group "$AzResourceGroup" --server $AzServerName --yes
  if ($lastexitcode -ne 0) { continue }

  sqlpackage.exe /a:import /tcs:"Data Source=tcp:$AzServerName.database.windows.net,1433;Initial Catalog=$db;User Id=$AzUserName;Password=$pwd" /sf:$filename /p:DatabaseEdition=Standard /p:DatabaseServiceObjective=S4 #/d:True
  # You may want to enable `/d:True` flag if the utility fails with no good explanation to why
  if ($lastexitcode -ne 0) { continue }

  # add the DB to elastic pool
  Write-Host "Moving to pool ..." -ForegroundColor Yellow
  az sql db create --name $db --resource-group "$AzResourceGroup" --elastic-pool "$AzPoolName"  --server $AzServerName
  if ($lastexitcode -ne 0) { continue }

  # rename the .bacpac file so that doesn't get imported again
  Move-Item -Path $filename -Destination "_$filename"
}
```

## Congratulations - you are done

All databases should have been imported into AZ SQL pool by the above script and into an Azure Elastic Pool. You can connect to them from your applications to start testing.

----

*This post is based on my recent experience migrating a real estate management system with hundreds of MS SQL databases from on-prem to Azure SQL. Read my other articles for more learnings from that project.*

*I realise that this article makes little sense outside the narrow context of migrating a large number of MS SQL DBs to Azure and is hard to comprehend. It took me quite some time to figure out the right merge process, so I decided that it's better to share what I learned even in its current form. It may still save someone a lot of time and effort.*