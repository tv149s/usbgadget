# Audit setup before reboot

Date: 2026-02-15

This log records the changes made before reboot to trace boot config rewrites.

## Packages installed

- auditd
- libauparse0t64

## Services enabled

- auditd.service
- audit-rules.service

## Audit rules added

- Watch /boot/firmware/config.txt for write and attribute changes (key: bootcfg)
- Watch /boot/firmware/cmdline.txt for write and attribute changes (key: bootcmd)

Commands used:

- apt-get install -y auditd
- systemctl enable --now auditd
- auditctl -w /boot/firmware/config.txt -p wa -k bootcfg
- auditctl -w /boot/firmware/cmdline.txt -p wa -k bootcmd
