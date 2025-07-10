# ReadyNAS RNDU6000 LCD Status Scripts

This repository contains two Bash scripts designed to display system status information on the integrated LCD of the NetGear ReadyNAS RNDU6000 (ReadyNAS 6 Pro) NAS device.

## Features

Both scripts provide real-time system monitoring directly on your ReadyNAS LCD.

### `lcd_status_simple.sh` (Basic)

  * **Basic Status:** Displays disk usage, CPU usage, and RAM usage.
  * **Non-Root Friendly:** Designed to run without root privileges, making it suitable for less privileged users (though `tty` device permissions are still required).
  * **Visual Indicators:** Uses pseudo-graphic bars for all displayed metrics.


### `lcd_status_btrfs.sh` (Advanced)

  * **Comprehensive Status:** Displays Ethernet IP addresses during boot, disk usage, CPU usage, RAM usage, and BTRFS array operation status (scrubbing, balancing, defragmenting).
  * **RAID Health Alerts:** Shows a "RAID WARNING" banner on the LCD if any RAID array is detected as degraded.
  * **BTRFS Operation Tracking:** Indicates if Btrfs long-running operations (like scrub or balance) are active and shows their progress.
  * **Root Required:** This script needs to be run with root privileges due to its interaction with Btrfs commands and `/proc/mdstat` for RAID status.
  * **Visual Indicators:** Uses pseudo-graphic bars for resource usage, or percentage for BTRFS operations.

## LCD Display Information

These scripts are specifically tailored for the LCD display found on the NetGear ReadyNAS RNDU6000.

  * **LCD Port:** `/dev/ttyS1` (Serial Port 1)
  * **LCD Dimensions:** 128x32 pixels
  * **LCD Command System:** Custom serial protocol (commands like `E` for clear, `F` for font, `C` for cursor, `L` for text).
  * **Font Details:**
      * **Font 0 (Arial 9):** Variable width, approx. 21 chars/line.
      * **Font 1 (Arial 18):** Variable width, approx. 12 chars/line, good for banners.
      * **Font 2 (Monospace 5x8):** Fixed width, 21 chars/line, ideal for consistent data display.

## Permissions for LCD Device

For the scripts to write to the LCD, the user running them (e.g., `root` or your `cron` user) needs read/write access to `/dev/ttyS1`.

If you encounter "Permission denied" errors, you may need to add your user to the `tty` and `dialout` groups:

```bash
sudo usermod -a -G tty,dialout $USER
```

After running this command, **log out and log back in** for the changes to take effect.

## Installation and Usage

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/berouques/rndu6000_lcd_status.git
    cd rndu6000_lcd_status
    ```
2.  **Make scripts executable:**
    ```bash
    chmod +x lcd_status_btrfs.sh
    chmod +x lcd_status_simple.sh
    ```
3.  **Configure Mount Points (for `lcd_status_btrfs.sh`):**
    Open `lcd_status_btrfs.sh` and adjust `DISK1_MOUNT_POINT` and `DISK2_MOUNT_POINT` to match your Btrfs mount points.

## Cron Job Examples

It's recommended to run these scripts every minute using `cron` to keep the LCD display updated.

### For `lcd_status_btrfs.sh` (Requires Root)

Since `lcd_status_btrfs.sh` needs root access, add the cron job as the `root` user:

```bash
sudo crontab -e
```

Add the following line to the `crontab` file:

```cron
* * * * * /path/to/your/script/lcd_status_btrfs.sh >/dev/null 2>&1
```

Replace `/path/to/your/script/` with the actual path where you cloned the repository.

### For `lcd_status_simple.sh` (Non-Root)

You can add this cron job as your regular user:

```bash
crontab -e
```

Add the following line:

```cron
* * * * * /path/to/your/script/lcd_status_simple.sh >/dev/null 2>&1
```

Replace `/path/to/your/script/` with the actual path.

## Troubleshooting

  * **"Permission denied" errors:** Ensure the user running the script has appropriate permissions to `/dev/ttyS1` by adding them to the `tty` and `dialout` groups (see "Permissions for LCD Device" section).
  * **No output on LCD:** Verify the `LCD_DEVICE` path in the script is correct (`/dev/ttyS1`). Check the cron logs for any errors (remove `>/dev/null 2>&1` temporarily to see output).
  * **Incorrect Btrfs status:** Double-check the `DISK1_MOUNT_POINT` and `DISK2_MOUNT_POINT` variables in `lcd_status_btrfs.sh` match your actual Btrfs mount points.

## Contributing

Feel free to open issues or submit pull requests if you have improvements or bug fixes.

## License

This project is licensed under the MIT License - see the `LICENSE` file for details.

-----
