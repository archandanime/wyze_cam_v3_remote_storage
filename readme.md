## Features

- SSH(dropbear), SFTP, Rsync, File server(dufs)
- Firmware update block
- Works with latest firmware

## How to install

**Step 0:** Backup all your stock partitions using [wz_flash-helper](https://github.com/archandanime/wz_flash-helper/)

**Step 1:** Install latest stock firmware and make it work.

**Step 2:** Use wz_flash-helper restore operation to flash `kernel`, `rootfs` and `app` partitions.

**Step 3:** Connect to your camera using SSH. `username`:`password` is `root`:`root`

## Configure SSH public key authentication

You can setup SSH public key authentication by creating `/configs/authorized_keys` with your public key. If the `authorized_keys` file exists, dropbear only allows public key authentication.

In case you set the `authorized_keys` file incorrectly, restore the backed up `configs` partition using wz_flash-helper.

## Configure File server

By default, dufs has no authentication and servers `alarm`, `record` and `time_lapse` firectories on SD card. To configure authentication, server path and users, copy `/etc/dufs.yaml` to `/configs/dufs.yaml` and edit it.

**Credit:** @gtxaspec for iperf3 binary, I was unable to compile it using Buildroot
