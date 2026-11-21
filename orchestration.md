# Orchestration

### Schedule

Each day at 9:00 UTC, after both deliveries

### Order

orders + clients, then staging, then cleaning, then deduplication, then validation, then join, then ASSERT checks, then publication, then checkpoint update

### The source was too late

Wait until 11:00 UTC, then send notification and keep the last report version

### Temporary glitch

Repeat up to 3 times with pauses at 5, 10 and 20 minutes, then send notification

### Quality control failed

Do not repeat, do not publish. Send the notification to the data owner

### Publication

Only if all the steps and checks were passed

### New Data

Get rows with source_row_id, which should be greater than saved checkpoint

### Corrections

MERGE by order_id + line_no. If new key, then insert. If a more recent version, then update. A recent version became invalid or cancelled, then remove from the table

### Restart

It should not make duplicates, because MERGE is working by key and updates only more recent versions

### Checkpoint

Moving it only after a successful publication

