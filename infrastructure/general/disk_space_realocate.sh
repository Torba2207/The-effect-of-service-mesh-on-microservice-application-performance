#!/bin/bash
for ip in 10.29.20.120; do #10.29.20.111 10.29.20.112 10.29.20.113; do
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