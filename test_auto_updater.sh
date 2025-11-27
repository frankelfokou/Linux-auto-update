#!/bin/bash

# Interrompe se un comando fallisce
set -e
set -o pipefail


REAL_USER="frankel"
HOME_VAR="/home/frankel/.var/auto_updater"
LOG_FILE="$HOME_VAR/auto_updater.log"

# Ottieni ID utente per il bus DBUS
USER_ID=$(id -u "$REAL_USER")
# =================================================

DEBUG_MODE=1

# --- Notification Function ---
send_notification() {
    local message="$1"

    # 1. ESCAPING DEL MESSAGGIO (Il fix cruciale)
    # Sostituisce ogni singolo apice ' con '\'' per non rompere il comando bash -c
    local safe_message
    safe_message=$(echo "$message" | sed "s/'/'\\\\''/g")
    
 

    # Esegue notify-send come l'utente reale.
    # NOTA IMPORTANTE:
    # 1. Passiamo le variabili (DBUS, DISPLAY, XDG) DENTRO il comando 'su -c'.
    # 2. Redirigiamo l'output di notify-send a /dev/null per evitare conflitti 
    #    con il file di log aperto da root.
    
    runuser -u "$REAL_USER" -- bash -c "
        export DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/${USER_ID}/bus'
        export DISPLAY=:0
        export XDG_RUNTIME_DIR='/run/user/${USER_ID}'
        
        notify-send -u normal \
            -i dialog-error \
            -a 'Weekend Updater' \
            'Update Failed!' \
            '$safe_message'
    " >/dev/null 2>&1 || true
}

# --- Error Handler ---
handle_error() {
    local exit_code=$?
    local line_no=$1
    local command="$2"
    
    # Disabilita set -e per evitare loop
    set +e 
    
    # Se siamo in DEBUG MODE, stampiamo l'errore anche a video
    if [ "$DEBUG_MODE" -eq 1 ]; then
        echo "!!! ERROR on line $line_no !!!" >&2
        echo "Command: $command" >&2
    fi
    
    local error_details=""
    
    if [ "$DEBUG_MODE" -eq 0 ]; then
        error_details=$(tail -n 3 "$LOG_FILE")
    else
        # Se Debug=1, il log potrebbe essere vuoto perché abbiamo stampato a video.
        error_details="Script eseguito in Debug Mode (output a schermo). Comando fallito: $command"
    fi

    # Esegui la notifica, ma reindirizza il suo output/errore al terminale originale
    # per assicurarti che funzioni anche se l'output dello script è rediretto a un file.
    # In questo modo, eventuali errori di 'notify-send' saranno visibili.
    send_notification "Exit Code: $exit_code | Line: $line_no | $error_details"

    exit "$exit_code"
}

# Trap errors: Passa numero riga e comando alla funzione
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR


# ================= PRE-CHECKS & SETUP =================

# 1. Creazione Directory e File Log
if [ ! -d "$HOME_VAR" ]; then
    mkdir -p "$HOME_VAR"
    chown -R "$REAL_USER":"$REAL_USER" "$HOME_VAR"
fi

# Crea il file di log vuoto (o lo resetta) all'avvio
: > "$LOG_FILE"
chown "$REAL_USER":"$REAL_USER" "$LOG_FILE"

# 2. GESTIONE OUTPUT (Il cuore della tua richiesta)
if [ "$DEBUG_MODE" -eq 0 ]; then
    exec >> "$LOG_FILE" 2>&1
else
    echo "--- DEBUG MODE ON: Output stampato a schermo ---"
fi

# 3. CHECK GIORNO DELLA SETTIMANA
# (Decommenta per attivare il blocco giorni)
# DAY_OF_WEEK=$(date +%u)
# if [[ "$DAY_OF_WEEK" -ne 6 && "$DAY_OF_WEEK" -ne 7 ]]; then
#     if [ "$DEBUG_MODE" -eq 1 ]; then echo "Non è weekend. Esco."; fi
#     exit 0
# fi

# 4. CHECK SE GIA ESEGUITO OGGI
TODAY_STAMP="$HOME_VAR/ran_update_$(date +%F)"

if [ -f "$TODAY_STAMP" ]; then
    if [ "$DEBUG_MODE" -eq 1 ]; then
        echo "Script già eseguito oggi ($TODAY_STAMP presente). Esco."
    fi
    exit 0
fi

# ================= START MAINTENANCE =================

echo "Starting Weekend Maintenance: $(date)"

# --- SYSTEM UPDATES (Root) ---
echo "--- Running DNF updates (Root) ---"
dnf updat --refresh -y
# || true impedisce il blocco se non c'è nulla da rimuovere
dnf autoremove -y || true
dnf clean all

# --- SYSTEM FLATPAK UPDATES (Root) ---
echo "--- Running System Flatpak updates (Root) ---"
flatpak update -y
flatpak uninstall --unused -y || true

# --- HOMEBREW & USER FLATPAK (User) ---
echo "--- Running Homebrew and User Flatpak updates (User: $REAL_USER) ---"

# Fix permessi brew se necessario
if [ -d "/home/linuxbrew/.linuxbrew" ]; then
    chown -R "$REAL_USER" /home/linuxbrew/.linuxbrew
fi

# Switch to user
su - "$REAL_USER" -c "
    set -e
    
    echo 'User context switched. Current user: $(whoami)'

    # HOMEBREW
    export NONINTERACTIVE=1
    if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
        /home/linuxbrew/.linuxbrew/bin/brew upgrade
        /home/linuxbrew/.linuxbrew/bin/brew autoremove || true
    fi

    # USER FLATPAK
    export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\"
    
    flatpak update --user -y
    flatpak uninstall --unused --user -y || true
"

# ================= FINISH =================

# Crea Stamp File
touch "$TODAY_STAMP"
chown "$REAL_USER":"$REAL_USER" "$TODAY_STAMP"

# Pulizia vecchi stamp (> 7 giorni)
find "$HOME_VAR" -type f -name "ran_update_*" -mtime +7 -delete

echo "Maintenance Complete."