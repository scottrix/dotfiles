# shellcheck shell=bash
# Helpers shared by install and steps/*.sh. Source this file; don't run it.
#
#   DOTFILES_DIR   the repo checkout          DRY_RUN=1      print changes only
#   BACKUP_DIR     where replaced files go     WARNINGS_FILE  warnings for the summary

: "${DOTFILES_DIR:=$HOME/.local/share/dotfiles}"
: "${DOTFILES_STATE:=$HOME/.local/state/dotfiles}"
: "${BACKUP_DIR:=$DOTFILES_STATE/backup/$(date +%Y%m%d-%H%M%S)}"
: "${WARNINGS_FILE:=$DOTFILES_STATE/warnings}"
: "${DRY_RUN:=0}"

say() { printf '    %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() {
    printf '    ! %s\n' "$*" >&2
    mkdir -p "$(dirname "$WARNINGS_FILE")"
    printf '%s\n' "$*" >> "$WARNINGS_FILE"
}

# run CMD...  run CMD, or just print it under --dry-run
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '    [dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}
srun() { run sudo "$@"; }

# backup PATH  move an existing user file, dir or link into BACKUP_DIR
backup() {
    local path=$1 rel
    [ -e "$path" ] || [ -L "$path" ] || return 0
    rel=${path#"$HOME"/}
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run mv "$path" "$BACKUP_DIR/$rel"
    say "backed up $path"
}

# link REPO_PATH DEST  symlink DOTFILES_DIR/REPO_PATH at DEST
link() {
    local src=$DOTFILES_DIR/$1 dest=$2
    [ -e "$src" ] || die "not in repo: $1"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        return 0
    fi
    backup "$dest"
    run mkdir -p "$(dirname "$dest")"
    run ln -s "$src" "$dest"
    say "linked $dest"
}

# put DEST [MODE] < CONTENT  write a generated user file when its content changes
put() {
    local dest=$1 mode=${2:-644} tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 0
    fi
    backup "$dest"
    if [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] write $dest"
        rm -f "$tmp"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    install -m "$mode" "$tmp" "$dest"
    rm -f "$tmp"
    say "wrote $dest"
}

# render TEMPLATE 'VARLIST'  print templates/TEMPLATE with only the listed ${VARS} replaced
render() {
    envsubst "$2" < "$DOTFILES_DIR/templates/$1"
}

# sys_backup FILE  keep the original of a system file as FILE.dotfiles-bak (first time only)
sys_backup() {
    [ -e "$1" ] || return 0
    sudo test -e "$1.dotfiles-bak" && return 0
    srun cp -a "$1" "$1.dotfiles-bak"
}

# sys_put FILE [MODE] < CONTENT  write a system file when its content changes
sys_put() {
    local dest=$1 mode=${2:-644} tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if sudo cmp -s "$tmp" "$dest" 2> /dev/null; then
        rm -f "$tmp"
        return 0
    fi
    sys_backup "$dest"
    srun install -D -m "$mode" "$tmp" "$dest"
    rm -f "$tmp"
    say "wrote $dest"
}

# sys_line FILE LINE  append LINE to a system file unless it is already there
sys_line() {
    sudo grep -qxF -- "$2" "$1" 2> /dev/null && return 0
    sys_backup "$1"
    if [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] add '$2' to $1"
        return 0
    fi
    printf '%s\n' "$2" | sudo tee -a "$1" > /dev/null
    say "added '$2' to $1"
}

# svc_add SERVICE RUNLEVEL  enable an OpenRC service unless it already is
svc_add() {
    # Exact match on the service-name column; awk reads all input, so no SIGPIPE under pipefail.
    if rc-update show "$2" 2> /dev/null | awk -v s="$1" '$1 == s { f = 1 } END { exit !f }'; then
        return 0
    fi
    srun rc-update add "$1" "$2"
}

# pkgs_from FILE  package names in packages/FILE, without comments or blank lines
pkgs_from() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$DOTFILES_DIR/packages/$1" | grep -v '^$' || true
}
