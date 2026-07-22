# Lab 11 — Permissions & ACLs

**Goal:** control who can access an HDFS path with **POSIX permissions** (owner/group/other) and,
for finer control, **extended ACLs** that grant specific named users.

## The ideas

Unlike the other labs (which disable permission checks for convenience), this one turns them **on**
(`dfs.permissions.enabled=true`) so denials really happen.

### POSIX permissions
Every file/dir has an **owner**, a **group**, and `rwx` bits for owner/group/**other** — e.g. mode
`750` means owner `rwx`, group `r-x`, everyone else nothing. A user who is neither the owner nor in
the group falls under "other" and is denied.

### Extended ACLs
POSIX bits can't say "…but also let *bob* in." **ACLs** add per-user/per-group entries on top:
`hdfs dfs -setfacl -m user:bob:r-x /proj` grants bob read+execute without changing the owner, group,
or the `other` bits. `getfacl` lists them.

> The HDFS **superuser** (the identity running the NameNode — `root` here) bypasses all checks, so
> the demo tests access as ordinary users via `HADOOP_USER_NAME=bob …`.

## Run it

```bash
make up
make demo      # deny bob by permissions, grant him via an ACL, keep carol out
make verify    # automated PASS/FAIL checks
make clean
```

## What to look for

- `hdfs dfs -getfacl /proj` shows both the base permissions and any `user:<name>:` ACL entries.
- Running a command as another user: `HADOOP_USER_NAME=bob hdfs dfs -ls /proj`.

## What `make verify` checks

1. `bob` is **denied** on a `750` directory he doesn't own.
2. An **ACL** `user:bob:r-x` is added and shown by `getfacl`.
3. `bob` can **now access** the directory.
4. `carol` (no ACL entry) is **still denied** — the grant is user-specific.
