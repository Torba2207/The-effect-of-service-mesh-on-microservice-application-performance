= Worker preparation
== Step 1 increasing disk space
Now we have up to 10GB of disk space on each worker, but since we need also prometheus and grafana on them we need to increase it to 25 GB.
```bash
for ip in 10.29.20.111 10.29.20.112 10.29.20.113; do
  echo -e "\n======================================"
  echo "EXPANDING DISK ON NODE: $ip"
  echo "======================================"
  
  # 1. Tell LVM to use 100% of the unallocated free space
  ssh -i ~/Documents/PG/Projects/.sshkeys/pgPB root@$ip "lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv"
  
  # 2. Tell the filesystem to stretch to match the new LVM size
  ssh -i ~/Documents/PG/Projects/.sshkeys/pgPB root@$ip "resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv"
  
  # 3. Print the new disk size
  echo -e "\nNew Disk Size:"
  ssh -i ~/Documents/PG/Projects/.sshkeys/pgPB root@$ip "df -h /"
done
```

Expected output:
```
======================================
EXPANDING DISK ON NODE: 10.29.20.111
======================================
  Size of logical volume ubuntu-vg/ubuntu-lv changed from 10.97 GiB (2809 extents) to <21.95 GiB (5618 extents).
  Logical volume ubuntu-vg/ubuntu-lv successfully resized.
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/mapper/ubuntu--vg-ubuntu--lv is mounted on /; on-line resizing required
old_desc_blocks = 2, new_desc_blocks = 3
The filesystem on /dev/mapper/ubuntu--vg-ubuntu--lv is now 5752832 (4k) blocks long.


New Disk Size:
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   22G  6.9G   14G  34% /

======================================
EXPANDING DISK ON NODE: 10.29.20.112
======================================
  Size of logical volume ubuntu-vg/ubuntu-lv changed from 10.97 GiB (2809 extents) to <21.95 GiB (5618 extents).
  Logical volume ubuntu-vg/ubuntu-lv successfully resized.
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/mapper/ubuntu--vg-ubuntu--lv is mounted on /; on-line resizing required
old_desc_blocks = 2, new_desc_blocks = 3
The filesystem on /dev/mapper/ubuntu--vg-ubuntu--lv is now 5752832 (4k) blocks long.


New Disk Size:
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   22G  7.3G   14G  36% /

======================================
EXPANDING DISK ON NODE: 10.29.20.113
======================================
  Size of logical volume ubuntu-vg/ubuntu-lv changed from 10.97 GiB (2809 extents) to <21.95 GiB (5618 extents).
  Logical volume ubuntu-vg/ubuntu-lv successfully resized.
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/mapper/ubuntu--vg-ubuntu--lv is mounted on /; on-line resizing required
old_desc_blocks = 2, new_desc_blocks = 3
The filesystem on /dev/mapper/ubuntu--vg-ubuntu--lv is now 5752832 (4k) blocks long.


New Disk Size:
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   22G  6.8G   14G  33% /
```