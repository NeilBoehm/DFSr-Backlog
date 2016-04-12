# DFSr-Backlog
Checks backlog counts for every DFS replication group.
Version one (Backlog.ps1) was single threaded, in our environment it runs for 4+ hours.
Version two (Backlog-v2.ps1) is using jobs and runs in roughly half the time as version one.
