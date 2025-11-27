# Linux Auto-Updater Script

## Project Overview

This project consists of a sophisticated Bash script designed to automate weekend system maintenance tasks on a Fedora-based Linux machine. It handles system and user-level package updates, error handling, and user notifications. The script is intended to be run as a privileged user (root) via a scheduler like `cron` or a systemd timer.

The repository contains two scripts:

* `auto_updater.sh`: The main production script. It runs silently on weekends, logging all output to a file.
* `test_auto_updater.sh`: A testing version of the script with `DEBUG_MODE` enabled, which prints all output directly to the terminal for easy debugging.

---

## Core Features

* **Automated & Comprehensive Updates**: The script updates `dnf` packages, system-level Flatpaks, user-level Flatpaks, and Homebrew packages.
* **Weekend Execution**: The production script is configured to run only on Saturdays and Sundays.
* **Idempotent Execution**: It includes a check to ensure it only runs once per day, creating a timestamp file upon successful completion.
* **Robust Error Handling**: The script uses `set -e` to exit immediately on any command failure. A `trap` is set to catch these errors, execute a cleanup/notification function, and then exit.
* **Desktop Notifications on Failure**: If any part of the update process fails, the script sends a desktop notification to the specified user. This is achieved by intelligently switching from the `root` context to the user's context and exporting the necessary environment variables (`DBUS_SESSION_BUS_ADDRESS`, `DISPLAY`) to connect to the user's desktop session.
* **Context Switching**: The script starts as `root` to perform system-wide updates and then uses `su - <user>` to switch to the regular user context for updating user-specific packages like Homebrew and user Flatpaks.
* **Logging and Debugging**: By default, all standard output and errors are redirected to a log file (`/home/frankel/.var/auto_updater/auto_updater.log`). A `DEBUG_MODE` flag can be set to `1` to bypass logging and print output to the console instead.
* **Automatic Cleanup**: The script automatically removes orphaned packages (`dnf autoremove`, `flatpak uninstall --unused`) and cleans up old log/timestamp files to conserve disk space.
* **DNF Lock Handling**: Before running `dnf` commands, the script checks if DNF is locked by another process. It will wait for up to 60 seconds for the lock to be released before timing out and sending an error notification.

---

## Detailed Update Process

The update process is executed in a specific, logical order to ensure proper permissions and separation of concerns between system and user contexts.

### 1. Pre-Checks and Setup (Executed as `root`)

1. **Set Strict Mode**: The script begins with `set -e` and `set -o pipefail`, ensuring that it will stop immediately if any command fails.
2. **Error Trap**: An error trap is set for the `ERR` signal. If a command fails, it calls the `handle_error` function, passing the line number and the failed command as arguments.
3. **Directory and Log Setup**: It ensures the logging directory (`/home/frankel/.var/auto_updater`) exists and creates an empty log file for the current run.
4. **Output Redirection**: If not in debug mode, the script redirects all subsequent `stdout` and `stderr` to the log file.
5. **Weekend Check**: The production script checks if the current day is a Saturday or Sunday. If not, it exits silently. This check is disabled in the `test_auto_updater.sh` script.
6. **Daily Run Check**: It checks for the existence of a timestamp file (e.g., `ran_update_2025-11-27`). If the file for the current date is found, the script exits, preventing multiple runs in the same day.

### 2. System-Level Maintenance (Executed as `root`)

1. **DNF Updates**:
   * Checks for an active `dnf` lock and waits if necessary.
   * Refreshes package metadata and updates all installed `dnf` packages (`dnf update --refresh -y`).
   * Removes orphaned packages that are no longer required (`dnf autoremove -y`).
   * Cleans all cached package data (`dnf clean all`).
2. **System Flatpak Updates**:
   * Updates all system-wide Flatpak applications (`flatpak update -y`).
   * Uninstalls any unused Flatpak runtimes (`flatpak uninstall --unused -y`).

### 3. User-Level Maintenance (Executed as `frankel`)

1. **Switch to User**: The script uses `su - "frankel" -c "..."` to execute a block of commands as the non-root user `frankel`. This block also has `set -e` to maintain script integrity.
2. **Homebrew Updates**:
   * Updates all Homebrew-installed packages (`brew upgrade`).
   * Removes old and unused formula versions (`brew autoremove`).
   * Cleans up old downloads and logs (`brew cleanup`).
3. **User Flatpak Updates**:
   * Updates all Flatpak applications installed for the user (`flatpak update --user -y`).
   * Uninstalls any unused user-specific Flatpak runtimes (`flatpak uninstall --unused --user -y`).

### 4. Finalization (Executed as `root`)

1. **Create Timestamp**: Upon successful completion of all previous steps, the script creates the daily timestamp file (e.g., `ran_update_2025-11-27`) to prevent re-execution.
2. **Clean Old Timestamps**: It finds and deletes any timestamp files that are more than 7 days old, keeping the logging directory clean.
3. **Completion Message**: A final "Maintenance Complete" message is logged, and the script exits successfully.
