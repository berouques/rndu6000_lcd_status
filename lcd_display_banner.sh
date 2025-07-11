#!/bin/bash
# filename: lcd_display_banner.sh
# version: 0.1.3
# date: 2025-07-11 02:26
# author: Le Berouque
# github: https://github.com/berouques/rndu6000_lcd_status/
# license: MIT

# This script is designed for the NetGear ReadyNAS RNDU6000 to display a single word
# as a large banner on its integrated LCD.
# It takes one argument: the word to display.
# Intended to be used via cron or other utilities for displaying quick messages like "Hello."
#
# Usage: ./lcd_display_banner.sh "YourWord"
# Example for cron:
# @reboot /path/to/your/script/lcd_display_banner.sh "Hello." >/dev/null 2>&1
#
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

# Configuration
LCD_DEVICE="/dev/ttyS1"

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

# Prints a centered banner on the LCD using Font 1 (variable width, large). Clears screen first.
# Arg: $1 = text_string
lcd_print_banner() {
    local text_string="$1"
    
    # Try to clear the screen
    if ! lcd_clear; then
        log_error "Failed to clear LCD. Aborting banner display."
        return 1
    fi

    # Try to set font to 1
    if ! lcd_set_font 1; then
        log_error "Failed to set font 1. Aborting banner display."
        return 1
    fi

    log_message "Printing banner (Font 1): '$text_string'"
    # Note: Centering for variable width font is complex without knowing pixel width of string.
    # We will just print at X=0, which usually looks fine for short banners.
    local hex_x=$(printf "%02x" 0)
    local hex_y=$(printf "%02x" 0) # Start at top for banners
    
    echo "C${hex_x} ${hex_y}" > "$LCD_DEVICE" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to set cursor position on LCD device '$LCD_DEVICE'."
        return 1
    fi

    echo "L${text_string}" > "$LCD_DEVICE" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to write string to LCD device '$LCD_DEVICE'."
        return 1
    fi
    sleep 0.5 # Longer sleep for banners
    return 0
}

# --- Main Logic ---

main() {
    if [ -z "$1" ]; then
        log_error "Usage: $0 \"<word_to_display>\""
        log_error "No word provided. Exiting."
        exit 1
    fi

    local word_to_display="$1"
    log_message "Attempting to display banner: \"$word_to_display\""

    if lcd_print_banner "$word_to_display"; then
        log_message "Banner displayed successfully."
    else
        log_error "Failed to display banner."
        exit 1
    fi
}

# --- Script Execution ---
# Call the main function with all provided arguments
main "$@"

exit 0
