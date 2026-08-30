---
layout: page
title: "git"
permalink: /git
created: 2026/08/30
updated: 2026/08/30
review_by:
status: seedling
---

I tend to favor working with a variant of [GitFlow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow) attempts at other branching strategies always seem to evolve to basically becoming GitFlow over time. The dedicated branch for main (=production) works well in a managed services scenario for a production data platform.

I am often working with teams or individuals who do not have a great familiarity with source control. One of the best sites I have found to recommend to people picking up git is https://learngitbranching.js.org/.

## Useful Git Commands
### git config
```PowerShell
git config user.name "Your Name Here"
git config user.email your@email.example
```
set the username and email being committed as per repo.
For (global) default email (which is configured in your ~/.gitconfig):

```PowerShell
git config --global user.name "Your Name Here"
git config --global user.email your@email.example
```

```PowerShell
git config --global push.autoSetupRemote true
```
Sets a global flag to always automatically set the remote upstream on the Pc that ran it

### git remote prune origin
Removes local references to remote branches that have been deleted
This can then be followed up with the following powershell script to list the branches that should be deleted
```PowerShell
git branch -vv | Select-String ': gone\]' | ForEach-Object { ($_.ToString().Trim() -split '\s+')[0] }
```
These can then be formally deleted by running
```PowerShell
git branch -vv | Select-String ': gone\]' | ForEach-Object { ($_.ToString().Trim() -split '\s+')[0] } | ForEach-Object { git branch -D $_ }
```
### Undoing locally committed changes
Useful if accidentally committing to the wrong branch, especially if that branch as policies protecting against direct commits on the remote. 
```PowerShell
git reset --keep HEAD~1
```
Resets the files which are different between the **current** `HEAD` and the previous commit
