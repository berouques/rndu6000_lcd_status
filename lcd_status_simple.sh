#!/bin/bash
# filename: lcd_status_simple.sh
# version: 0.9.14
# date: 2025-07-09 23:04
# author: Le Berouque
# github: https://github.com/berouques/rndu6000_lcd_status
# license: MIT

# This script is designed for the NetGear ReadyNAS RNDU6000 to display system status information on its integrated LCD:
# - displays disk usage, CPU usage, RAM usage
# - shows visual bar indicators on the LCD
# - intended to run from cron WITHOUT root access level (but needs special permissions for user to access tty device)

# --- LCD Display Information ---
# This script is designed for the LCD display found on the NetGear ReadyNAS RNDU6000 (ReadyNAS 6 Pro).
# LCD Port: /dev/ttyS1 (Serial Port 1)
# LCD Dimensions: 128x32 pixels
# LCD Command System: Custom serial protocol.
#   - 'E': Clear screen
#   - 'F <font_id>': Set font (0, 1, 2)
#   - 'C<hex_x> <hex_y>': Set cursor position (e.g., C00 00 for top-left)
#   - 'L<string>': Display string at current cursor position
#   NB: a delay after the command is highly recommended (as an example, "sleep 0.2")
# Font Details:
#   - Font 0 (Arial 9, variable width): Not recommended for precise alignment. Can fit ~21 chars per line.
#     Line height: Approx. 10 pixels.
#   - Font 1 (Arial 18, variable width): Suitable for large banners. Can fit ~12 chars per line.
#     Line height: Approx. 18 pixels.
#   - Font 2 (Monospace 5x8, fixed width): Ideal for technical data, ensures consistent spacing.
#     Characters per line: 21 (128 pixels / 5 pixels/char = 25.6, but due to internal spacing, 21 is safe).
#     Line height: 8 pixels.
#     Recommended line Y coordinates for Font 2: 0, 8, 16, 24 (or 0, 10, 20 for slightly more spacing)

# --- Permissions for LCD Device ---
# The user running this script (e.g., root or a cron user) needs read/write access to /dev/ttyS1.
# If you encounter "Permission denied" errors, add your user to the 'tty' and 'dialout' groups:
# > sudo usermod -a -G tty,dialout $USER
# Log out and log back in for changes to take effect.

# --- Cron Job Examples ---
# 
# To add a cron job: 
# > crontab -e
#
# To run every minute (recommended):
# * * * * * /path/to/your/script/lcd_status_simple.sh >/dev/null 2>&1
#


# --- Configuration ---
LCD_DEVICE="/dev/ttyS1"
MAX_BAR_LENGTH=16 # Максимальная длина псевдографического бара (без символов метки и '|')
DISK_PATH="/srv/dev-disk-by-uuid-050ee224-5353-4c37-9809-31b3fc627fcc"

# --- Functions ---

clear_lcd() {
    echo "E" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.1
}

# Function to send a command to the LCD
set_font() {
    local command="$1"
    echo "F $command" > "$LCD_DEVICE" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to write to LCD device '$LCD_DEVICE'. Check permissions." >&2
    fi
    sleep 0.1
}

print_lcd() {
    local x=$1
    local y=$2
    local text_string="$3"

    set_font 2

    # Convert decimal coordinates to two-digit hexadecimal strings, with leading zeros.
    # The LCD protocol expects hexadecimal values for coordinates.
    local hex_x=$(printf "%02x" "$x")
    local hex_y=$(printf "%02x" "$y")

    # Set the cursor position on the LCD.
    echo "C${hex_x} ${hex_y}" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.1

    # Display the string on the LCD.
    echo "L${text_string}" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.2
}


print_banner() {
    local text_string="$1"

    clear_lcd
    set_font 1

    echo "C00 00" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.1

    # Display the string on the LCD.
    echo "L${text_string}" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.2
}


# Function to draw a pseudo-graphic bar
# Args: $1 = current_value, $2 = max_value, $3 = bar_max_chars
build_bar_string() {
    local current_value=$1
    local max_value=$2
    local bar_max_chars=$3

    local percentage=0
    if (( max_value > 0 )); then
        percentage=$(( (current_value * 100) / max_value ))
    fi

    local filled_chars=$(( (percentage * bar_max_chars) / 100 ))
    # Ensure filled_chars doesn't exceed bar_max_chars
    if (( filled_chars > bar_max_chars )); then
        filled_chars=$bar_max_chars
    fi

    local empty_chars=$(( bar_max_chars - filled_chars ))

    local bar_string=""
    for (( i=0; i<filled_chars; i++ )); do
        bar_string+="#"
    done
    for (( i=0; i<empty_chars; i++ )); do
        bar_string+=" "
    done
    echo "${bar_string}|"
}

# --- Main Script ---

echo "INFO: Starting LCD status update script at $(date)"

# 1. Get CPU Load (1-minute average)
# For a 4-core CPU, a load average of 4.00 means 100% utilization.
# We'll normalize the load average by the number of CPU cores.
CPU_LOAD_RAW=$(/usr/bin/uptime | /usr/bin/awk -F'load average: ' '{print $2}' | /usr/bin/awk '{print $1}' | /usr/bin/sed 's/,//')
CPU_CORES=$(/usr/bin/nproc)
# Convert load average to an integer for calculation (e.g., 0.50 -> 50)
CPU_LOAD_INT=$(echo "$CPU_LOAD_RAW * 100" | /usr/bin/bc | /usr/bin/cut -d'.' -f1)
CPU_MAX_INT=$(( CPU_CORES * 100 ))

CPU_BAR=$(build_bar_string "$CPU_LOAD_INT" "$CPU_MAX_INT" "$MAX_BAR_LENGTH")
CPU_PERCENTAGE=$(( (CPU_LOAD_INT * 100) / CPU_MAX_INT ))

# 2. Get Memory Usage (in MB)
MEM_INFO=$(/usr/bin/free -m | /usr/bin/awk '/Mem:/ {print $3, $2}')
USED_MEM=$(echo "$MEM_INFO" | /usr/bin/awk '{print $1}')
TOTAL_MEM=$(echo "$MEM_INFO" | /usr/bin/awk '{print $2}')

MEM_BAR=$(build_bar_string "$USED_MEM" "$TOTAL_MEM" "$MAX_BAR_LENGTH")
MEM_PERCENTAGE=$(( (USED_MEM * 100) / TOTAL_MEM ))

# 3. Get Disk Space Usage for /srv/dev-disk-by-uuid-050ee224-5353-4c37-9809-31b3fc627fcc (in 1K blocks)
DISK_INFO=$(/usr/bin/df -P "$DISK_PATH" | /usr/bin/awk 'NR==2 {print $3, $2}')
USED_DISK=$(echo "$DISK_INFO" | /usr/bin/awk '{print $1}')
TOTAL_DISK=$(echo "$DISK_INFO" | /usr/bin/awk '{print $2}')

DISK_BAR=$(build_bar_string "$USED_DISK" "$TOTAL_DISK" "$MAX_BAR_LENGTH")
DISK_PERCENTAGE=$(( (USED_DISK * 100) / TOTAL_DISK ))

# --- Output to Console ---
echo "--- System Status ---"
echo "CPU Load (1min): ${CPU_LOAD_RAW} (approx. ${CPU_PERCENTAGE}%)"
echo "C ${CPU_BAR}"
echo "Memory Used: ${USED_MEM}MB / ${TOTAL_MEM}MB (${MEM_PERCENTAGE}%)"
echo "M ${MEM_BAR}"
echo "Disk /srv/dev-disk-by-uuid-050ee224-5353-4c37-9809-31b3fc627fcc Used: $(/usr/bin/df -h "$DISK_PATH" | /usr/bin/awk 'NR==2 {print $3}') / $(/usr/bin/df -h "$DISK_PATH" | /usr/bin/awk 'NR==2 {print $2}') (${DISK_PERCENTAGE}%)"
echo "D ${DISK_BAR}"
echo "---------------------"

# --- Output to LCD ---

# Clear screen
clear_lcd

# Set font to Monospace 5x8 (F 2)
set_font 2

# Line 1: CPU
print_lcd 0 0 "CPU ${CPU_BAR}"

# Line 2: Memory
print_lcd 0 10 "MEM ${MEM_BAR}"

# Line 3: Disk
print_lcd 0 20 "DSK ${DISK_BAR}"

echo "INFO: LCD update complete."

exit 0
