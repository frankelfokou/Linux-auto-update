# Linux Auto-Updater Script

## Project Overview

Questo progetto consiste in un sofisticato script Bash progettato per automatizzare le attività di manutenzione del sistema durante il fine settimana su una macchina Linux basata su Fedora. Gestisce gli aggiornamenti dei pacchetti a livello di sistema e utente, la gestione degli errori e le notifiche all'utente. Lo script è pensato per essere eseguito come utente privilegiato (root) tramite un pianificatore come `cron` o un timer di systemd.

---

## Scripts Inclusi

Il repository contiene due versioni dello script:

*   `auto_updater.sh`: Lo script principale di produzione.
    *   **Modalità Silenziosa**: Gira in background, registrando tutto l'output su un file di log.
    *   **Esecuzione nel Weekend**: È configurato per essere eseguito solo il sabato e la domenica.
    *   **Log**: L'output viene salvato in `/home/frankel/.var/auto_updater/auto_updater.log`.

*   `test_auto_updater.sh`: Una versione di test dello script.
    *   **Modalità Debug**: Stampa tutto l'output direttamente sul terminale per un facile debug.
    *   **Esecuzione Immediata**: Il controllo del giorno della settimana è disabilitato, quindi può essere eseguito in qualsiasi giorno.

---

## Installazione e Pianificazione

1.  **Rendi lo script eseguibile**: Copia lo script `auto_updater.sh` in una directory appropriata (es. `/usr/local/bin/` o `/home/frankel/.bin/`) e assicurati che sia eseguibile.

    ```bash
    sudo cp auto_updater.sh /usr/local/bin/auto_updater
    sudo chmod +x /usr/local/bin/auto_updater
    ```

2.  **Pianifica l'esecuzione**: Lo script deve essere eseguito da `root`. Puoi usare `cron` per pianificarne l'esecuzione. Apri la crontab di root con `sudo crontab -e` e aggiungi una delle seguenti righe:

    *   **Per eseguire lo script ogni ora** (lo script stesso si assicurerà di procedere solo una volta al giorno e solo nei weekend):
        ```cron
        0 * * * * /usr/local/bin/auto_updater
        ```
    *   **Per eseguire lo script a ogni riavvio**:
        ```cron
        @reboot /usr/local/bin/auto_updater
        ```

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

Il processo di aggiornamento viene eseguito in un ordine logico e specifico per garantire le autorizzazioni corrette e la separazione dei contesti tra sistema e utente.

### 1. Pre-Checks and Setup (Executed as `root`)

1. **Set Strict Mode**: The script begins with `set -e` and `set -o pipefail`, ensuring that it will stop immediately if any command fails.
2. **Error Trap**: An error trap is set for the `ERR` signal. If a command fails, it calls the `handle_error` function, passing the line number and the failed command as arguments.
3. **Directory and Log Setup**: It ensures the logging directory (`/home/frankel/.var/auto_updater`) exists and creates an empty log file for the current run.
4. **Output Redirection**: If not in debug mode, the script redirects all subsequent `stdout` and `stderr` to the log file.
5. **Weekend Check**: The production script checks if the current day is a Saturday or Sunday. If not, it exits silently. This check is disabled in the `test_auto_updater.sh` script.
6. **Daily Run Check**: It checks for the existence of a timestamp file (e.g., `ran_update_2025-12-01`). If the file for the current date is found, the script exits, preventing multiple runs in the same day.

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

1. **Create Timestamp**: Upon successful completion of all previous steps, the script creates the daily timestamp file (e.g., `ran_update_2025-12-01`) to prevent re-execution.
2. **Clean Old Timestamps**: It finds and deletes any timestamp files that are more than 7 days old, keeping the logging directory clean.
3. **Completion Message**: A final "Maintenance Complete" message is logged, and the script exits successfully.
