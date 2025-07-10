#!/bin/bash
# filename: lcd_status_btrfs.sh
# version: 0.4.9
# date: 2025-07-10 03:56
# author: Le Berouque
# github: https://github.com/berouques/rndu6000_lcd_status
# license: MIT

# This script is designed for the NetGear ReadyNAS RNDU6000 to display system status information on its integrated LCD:
# - displays ethernet address, disk usage, CPU usage, RAM usage, BTRFS running operation status
# - shows either number or visual bar indicators on the LCD
# - shows network interface IP addresses during the initial system boot phase for quick verification
# - intended to run from cron WITH root access level (and needs special permissions for user to access tty device)

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
# IMPORTANT: this script (lcd_status_btrfs.sh) must be run with as 'root' because it uses btrfs commands that need root access
#
# To add a cron job as a root: 
# > sudo crontab -e
#
# To run every minute (recommended):
# * * * * * /path/to/your/script/lcd_status_btrfs.sh >/dev/null 2>&1
#

# Configuration
LCD_DEVICE="/dev/ttyS1"
MAX_BAR_LENGTH=16     # Max length for pseudo-graphic bars
DISK1_MOUNT_POINT="/srv/dev-disk-by-uuid-050ee224-5353-4c37-9809-31b3fc627fcc"
DISK2_MOUNT_POINT="/srv/dev-disk-by-uuid-891ce6da-69be-4885-baa3-6dfaced60f09"
UPTIME_BANNER_THRESHOLD_SECONDS=300 # 5 minutes = 300 seconds


# --- Constants ---
# LCD Dimensions and Font Metrics
LCD_WIDTH=128
LCD_HEIGHT=32
FONT0_LINE_HEIGHT=10  # Approximate for Arial 9
FONT1_LINE_HEIGHT=18  # Approximate for Arial 18 (for banners)
FONT2_LINE_HEIGHT=10   # Fixed for Monospace 5x8
FONT2_CHAR_WIDTH=5    # Fixed for Monospace 5x8
FONT2_MAX_CHARS=$((LCD_WIDTH / FONT2_CHAR_WIDTH)) # Theoretical max, safer to use 21 as determined by testing.
FONT2_SAFE_CHARS=21   # Confirmed number of characters that fit for Font 2

# --- Utility Functions ---

# Function to log messages to console
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $message"
}

# Function to log errors to console
log_error() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $message" >&2
}

# --- LCD Control Functions ---

# Clears the LCD screen.
lcd_clear() {
    log_message "Clearing LCD screen."
    echo "E" > "$LCD_DEVICE" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to write to LCD device '$LCD_DEVICE'. Check permissions."
        return 1
    fi
    sleep 0.1
    return 0
}

# Sets the active font for the LCD.
# Arg: $1 = font_id (0, 1, or 2)
lcd_set_font() {
    local font_id="$1"
    log_message "Setting LCD font to $font_id."
    echo "F $font_id" > "$LCD_DEVICE" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to set font on LCD device '$LCD_DEVICE'."
        return 1
    fi
    sleep 0.1
    return 0
}

# Prints a string on the LCD using Font 0 (variable width, small).
# Arg: $1 = line_number (0-3 for typical 32px height)
# Arg: $2 = text_string
lcd_print_arial() {
    local line_number=$1
    local text_string="$2"
    local y_coord=$((line_number * FONT0_LINE_HEIGHT))
    lcd_set_font 0
    log_message "Printing (Font 0) line $line_number at Y=$y_coord: '$text_string'"
    local hex_x=$(printf "%02x" 0)
    local hex_y=$(printf "%02x" "$y_coord")
    echo "C${hex_x} ${hex_y}" > "$LCD_DEVICE" 2>/dev/null
    echo "L${text_string}" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.2
}

# Prints a centered banner on the LCD using Font 1 (variable width, large). Clears screen first.
# Arg: $1 = text_string
lcd_print_banner() {
    local text_string="$1"
    lcd_clear
    lcd_set_font 1
    log_message "Printing banner (Font 1): '$text_string'"
    # Note: Centering for variable width font is complex without knowing pixel width of string.
    # We will just print at X=0, which usually looks fine for short banners.
    local hex_x=$(printf "%02x" 0)
    local hex_y=$(printf "%02x" 0) # Start at top for banners
    echo "C${hex_x} ${hex_y}" > "$LCD_DEVICE" 2>/dev/null
    echo "L${text_string}" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.5 # Longer sleep for banners
}

# Prints a string on the LCD using Font 2 (monospace, fixed width).
# Arg: $1 = line_number (0-3 for typical 32px height)
# Arg: $2 = text_string
lcd_print_mono() {
    local line_number=$1
    local text_string="$2"
    local y_coord=$((line_number * FONT2_LINE_HEIGHT))
    lcd_set_font 2
    log_message "Printing (Font 2) line $line_number at Y=$y_coord: '$text_string'"
    local hex_x=$(printf "%02x" 0)
    local hex_y=$(printf "%02x" "$y_coord")
    echo "C${hex_x} ${hex_y}" > "$LCD_DEVICE" 2>/dev/null
    echo "L${text_string}" > "$LCD_DEVICE" 2>/dev/null
    sleep 0.2
}

# --- Data Formatting Functions ---

# Generates a pseudo-graphic bar string.
# Args: $1 = current_value, $2 = max_value, $3 = bar_max_chars
# Returns: String like "#####      |"
format_bar() {
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
        bar_string+=":"
    done
    # echo "${bar_string}|"
    echo "${bar_string}"
}

# Calculates and formats RAM usage as a bar.
# Returns: String with RAM usage bar.
get_ram_bar() {
    local mem_info=$(free -m | awk '/Mem:/ {print $3, $2}')
    local used_mem=$(echo "$mem_info" | awk '{print $1}')
    local total_mem=$(echo "$mem_info" | awk '{print $2}')
    format_bar "$used_mem" "$total_mem" "$MAX_BAR_LENGTH"
}

# Calculates and formats RAM usage as a percentage string.
# Returns: String like "83%"
get_ram_percentage_string() {
    local mem_info=$(free -m | awk '/Mem:/ {print $3, $2}')
    local used_mem=$(echo "$mem_info" | awk '{print $1}')
    local total_mem=$(echo "$mem_info" | awk '{print $2}')
    local percentage=$(( (used_mem * 100) / total_mem ))
    printf "%s%%" "$percentage"
}

# Calculates and formats CPU load (1-min average) as a bar.
# Returns: String with CPU load bar.
get_cpu_load_bar() {
    local cpu_load_raw=$(uptime | awk -F'load average: ' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local cpu_load_int=$(echo "$cpu_load_raw * 100" | bc | cut -d'.' -f1)
    local cpu_max_int=$(( cpu_cores * 100 )) # Max load for 100% utilization
    format_bar "$cpu_load_int" "$cpu_max_int" "$MAX_BAR_LENGTH"
}

# Calculates and formats CPU load (1-min average) as a percentage string.
# Returns: String like "83%"
get_cpu_load_percentage_string() {
    local cpu_load_raw=$(uptime | awk -F'load average: ' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local cpu_load_int=$(echo "$cpu_load_raw * 100" | bc | cut -d'.' -f1)
    local cpu_max_int=$(( cpu_cores * 100 ))
    local percentage=$(( (cpu_load_int * 100) / cpu_max_int ))
    printf "%s%%" "$percentage"
}

# Calculates and formats disk space usage for a given mount point as a bar.
# Arg: $1 = mount_point
# Returns: String with disk usage bar.
get_disk_space_bar() {
    local mount_point="$1"
    local disk_info=$(df -P "$mount_point" 2>/dev/null | awk 'NR==2 {print $3, $2}')
    local used_disk=$(echo "$disk_info" | awk '{print $1}')
    local total_disk=$(echo "$disk_info" | awk '{print $2}')
    format_bar "$used_disk" "$total_disk" "$MAX_BAR_LENGTH"
}

# Calculates and formats disk space usage for a given mount point as a percentage string.
# Arg: $1 = mount_point
# Returns: String like "79%"
get_disk_space_percentage_string() {
    local mount_point="$1"
    local disk_info=$(df -P "$mount_point" 2>/dev/null | awk 'NR==2 {print $3, $2}')
    local used_disk=$(echo "$disk_info" | awk '{print $1}')
    local total_disk=$(echo "$disk_info" | awk '{print $2}')
    local percentage=0
    if (( total_disk > 0 )); then
        percentage=$(( (used_disk * 100) / total_disk ))
    fi
    printf "%s%%" "$percentage"
}

# --- System Status Check Functions ---

# Checks if any RAID array is in a degraded state.
# Returns: 0 if any degraded array is found, 1 otherwise.
# Sets global variable 'degraded_md_device' to the name of the first degraded array found (e.g., md0).
check_raid_degraded() {
    degraded_md_device="" # Reset global variable
    local md_status=$(cat /proc/mdstat 2>/dev/null)
    # Look for lines containing array names (mdX) and a [U_] or [_U] pattern (indicating degraded)
    local degraded_array_name=$(echo "$md_status" | grep "md[0-9]" | grep -E "\[.*_.*\]|\[_.*\]" | awk '{print $1}' | head -n 1)

    if [ -n "$degraded_array_name" ]; then
        degraded_md_device="$degraded_array_name"
        log_message "Detected degraded RAID array: $degraded_md_device"
        return 0 # Return 0 for success (found degraded array)
    fi
    return 1 # Return 1 for failure (no degraded array)
}

# Checks for active Btrfs long operations (scrub, balance, defrag).
# Arguments:
#   $1 - Mount point to check (e.g., "/"). This is crucial for accurate status.
# Returns: String with operation name and progress (e.g., "Scrubbing 17%") or empty string if none.
get_btrfs_long_operation() {
    local mount_point="$1"
    local operation_status=""
    local percent=""

    # Return empty string if no mount point is provided
    if [ -z "$mount_point" ]; then
        return 1 # Indicate an error via exit code, but still return empty string
    fi

    # Check for btrfs scrub
    local scrub_status=$(btrfs scrub status "$mount_point" 2>/dev/null)
    if echo "$scrub_status" | grep -q "Status:\s*running"; then
        #percent=$(echo "$scrub_status" | grep -oP 'completed: \K[0-9]+(\.[0-9]+)?%' | sed 's/%//' | cut -d'.' -f1)
        #percent=$(echo "$scrub_status" | grep -oP '\(([0-9.]+%)' | head -n 1 | sed 's/[()%]//g' | cut -d'.' -f1)
        percent=$(echo "$scrub_status" | grep -oP '\((\d+)%' | head -n 1 | grep -oP '\d+')
        if [ -n "$percent" ]; then
            operation_status="Scrubbing ${percent}%"
        else
            operation_status="Scrubbing..."
        fi
        echo "$operation_status"
        return 0
    fi

    # Check for btrfs balance
    local balance_status=$(btrfs balance status "$mount_point" 2>/dev/null)
    if echo "$balance_status" | grep -q "Balance is running"; then
        # Попробуем извлечь процент из строки "total_progress" или "(XX% left)"
        percent=$(echo "$balance_status" | grep -oP 'total_progress: \K[0-9]+(\.[0-9]+)?%' | sed 's/%//' | cut -d'.' -f1)
        if [ -z "$percent" ]; then # Если не нашли в total_progress, ищем в "(XX% left)"
            percent=$(echo "$balance_status" | grep -oP '\(([0-9.]+%) left\)' | sed 's/[(% left)]//g' | cut -d'.' -f1)
        fi

        if [ -n "$percent" ]; then
            operation_status="Balancing ${percent}%"
        else
            operation_status="Balancing..."
        fi
        echo "$operation_status"
        return 0
    fi

    # Check for btrfs defrag
    if pgrep -f "btrfs filesystem defragment .* $mount_point" >/dev/null; then
        operation_status="Defragmenting" # No easy progress for defrag via btrfs status
        echo "$operation_status"
        return 0
    fi

    # If no operations found, return empty string
    echo ""
    return 0
}


# Gets the current uptime in seconds.
get_uptime_seconds() {
    awk '{print int($1)}' /proc/uptime
}

# Gets the hostname.
get_hostname() {
    hostname
}

# Gets the IPv4 address for a given interface.
# Arg: $1 = interface_name (e.g., eth0)
get_ipv4_addr() {
    local iface="$1"
    ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -n 1
}


# --- Main Logic ---

main() {
    log_message "Starting LCD status update script."

    local current_uptime_seconds=$(get_uptime_seconds)
    local degraded_array=""
    # Check if a RAID array is degraded. If so, degraded_md_device will be set.
    if check_raid_degraded; then
        degraded_array=$degraded_md_device
    fi
    local btrfs_status_dsk1=$(get_btrfs_long_operation "$DISK1_MOUNT_POINT")
    local btrfs_status_dsk2=$(get_btrfs_long_operation "$DISK2_MOUNT_POINT")

    # --- Determine what to display based on system state ---
    local line1_text=""
    local line2_text=""
    local line3_text=""

    if [ "$current_uptime_seconds" -lt "$UPTIME_BANNER_THRESHOLD_SECONDS" ]; then
        # System just started, show network info
        local hostname_val=$(get_hostname)
        local eth0_ip=$(get_ipv4_addr "eth0")
        local eth1_ip=$(get_ipv4_addr "eth1")

        line1_text="$hostname_val"
        line2_text="eth0: ${eth0_ip:-N/A}"
        line3_text="eth1: ${eth1_ip:-N/A}"
        
        log_message "Displaying boot info (Uptime: ${current_uptime_seconds}s)"
        log_message "Line 1: $line1_text"
        log_message "Line 2: $line2_text"
        log_message "Line 3: $line3_text"
        
        # Display on LCD
        lcd_clear
        lcd_print_mono 0 "$line1_text"
        lcd_print_mono 1 "$line2_text"
        lcd_print_mono 2 "$line3_text"
        
    elif [ -n "$degraded_array" ]; then
        # RAID is degraded, show warning banner
        line1_text="RAID WARNING"
        line2_text="$degraded_array" # This will now be like "md0" or "md1"

        log_message "Displaying RAID warning: $degraded_array"
        log_message "Line 1: $line1_text"
        log_message "Line 2: $line2_text"
        
        # Display on LCD using banners for impact
        lcd_print_banner "$line1_text"
        # Since banner clears screen, we need to re-set font and print second line
        lcd_print_mono 2 "$line2_text" # Using Font 2 for degraded array name
    else
        # Default status display
        local disk1_bar=$(get_disk_space_bar "$DISK1_MOUNT_POINT")
        local disk2_bar=$(get_disk_space_bar "$DISK2_MOUNT_POINT")
        local cpu_percentage=$(get_cpu_load_percentage_string)
        local ram_percentage=$(get_ram_percentage_string)

        if [ -n "$btrfs_status_dsk1" ]; then
            line1_text="DSK1 $btrfs_status_dsk1"
        else
            line1_text="DSK1 $(printf "%-16s" "$disk1_bar")" # Pad bar to MAX_BAR_LENGTH for consistent display
        fi

        if [ -n "$btrfs_status_dsk2" ]; then
            line2_text="DSK2 $btrfs_status_dsk2"
        else
            line2_text="DSK2 $(printf "%-16s" "$disk2_bar")" # Pad bar to MAX_BAR_LENGTH for consistent display
        fi

        line3_text="CPU  $(get_cpu_load_bar)"
        #line3_text=$(printf "CPU %-4s RAM %-4s" "$cpu_percentage" "$ram_percentage")

        log_message "Displaying default system status."
        log_message "Line 1: $line1_text"
        log_message "Line 2: $line2_text"
        log_message "Line 3: $line3_text"
        
        # Display on LCD
        lcd_clear
        lcd_print_mono 0 "$line1_text"
        lcd_print_mono 1 "$line2_text"
        lcd_print_mono 2 "$line3_text"
    fi

    log_message "LCD update complete."
}

# --- Script Execution ---
# Call the main function
main

exit 0
