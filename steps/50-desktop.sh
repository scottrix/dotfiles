#!/usr/bin/env bash
# labwc, waybar, foot, the theme, and the login layout.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/choices.sh
. "$DOTFILES_DIR/lib/choices.sh"

# The questions are asked before 20-packages installs the XKB layout list, so
# a typo (uk for gb) can only be caught now; labwc would fall back to us.
if [ -f "$XKB_RULES" ] && ! valid_layout "$KB_LAYOUT"; then
    warn "keyboard layout '$KB_LAYOUT' isn't in the XKB layout list ($XKB_RULES, section '! layout'), so the desktop and login screen fall back to us. Run $DOTFILES_DIR/install --from 40-session and give a layout from that list when asked (DF_KB_LAYOUT=... also works with --yes)"
fi

# first wired interface, for waybar's ethernet module
first_ethernet() {
    local dev
    for dev in /sys/class/net/*; do
        if [ -e "$dev/device" ] && [ ! -e "$dev/wireless" ] && [ ! -e "$dev/phy80211" ]; then
            basename "$dev"
            return
        fi
    done
    echo eth0
}

term_rules() {
    local n=1 x y
    for y in 0 391 782; do
        for x in 0 640 1280; do
            printf '    <windowRule identifier="startterm-%s" matchOnce="true">\n' "$n"
            printf '      <action name="SendToDesktop" to="1" follow="no"/>\n'
            printf '      <action name="MoveTo" x="%s" y="%s"/>\n' "$x" "$y"
            printf '      <action name="ResizeTo" width="630" height="360"/>\n'
            printf '    </windowRule>\n'
            n=$((n + 1))
        done
    done
}

# app_rule APP_ID DESKTOP  maximise the first window of APP_ID on DESKTOP
app_rule() {
    printf '    <windowRule identifier="%s" matchOnce="true">\n' "$1"
    printf '      <action name="SendToDesktop" to="%s" follow="no"/>\n' "$2"
    printf '      <action name="Maximize"/>\n'
    printf '    </windowRule>\n'
}

USER_ID=$(id -u)
ETH_IF=$(first_ethernet)
TERM_RULES=$(term_rules)
APP_RULES=$(app_rule "$BROWSER_ID" 2)
MAIL_MENU_ITEM='' MAIL_START=''
if [ -n "$MAIL_ID" ]; then
    APP_RULES+=$'\n'$(app_rule "$MAIL_ID" 3)
    MAIL_MENU_ITEM=$(printf '\t\t<item label="%s"> <action name="Execute">\n\t\t\t<execute>%s</execute>\n\t\t</action> </item>' "$MAIL_LABEL" "$MAIL_CMD")
    MAIL_START="$MAIL_CMD &>/dev/null &"
fi
export USER_ID ETH_IF TERM_RULES APP_RULES MAIL_MENU_ITEM MAIL_START

# shellcheck disable=SC2016
{
    render labwc/rc.xml '${TERM_RULES} ${APP_RULES}' | put "$HOME/.config/labwc/rc.xml"
    render labwc/menu.xml '${BROWSER_LABEL} ${BROWSER_CMD} ${MAIL_MENU_ITEM}' | put "$HOME/.config/labwc/menu.xml"
    render labwc/environment '${KB_LAYOUT} ${USER_ID}' | put "$HOME/.config/labwc/environment"
    render waybar/config.jsonc '${ETH_IF}' | put "$HOME/.config/waybar/config.jsonc"
    render bin/labwc_startup '${BROWSER_CMD} ${MAIL_START}' | put "$HOME/bin/labwc_startup" 755
}
link home/.config/labwc/autostart "$HOME/.config/labwc/autostart"
link home/.config/waybar/style.css "$HOME/.config/waybar/style.css"
link home/.config/foot/foot.ini "$HOME/.config/foot/foot.ini"
link home/.config/mako/config "$HOME/.config/mako/config"
link home/.local/share/themes/Clearlooks-3.4/openbox-3/themerc "$HOME/.local/share/themes/Clearlooks-3.4/openbox-3/themerc"
link home/bin/lock "$HOME/bin/lock"
# lock reads input devices to wake the blanked display; takes effect at next login.
id -nG "$USER" | tr ' ' '\n' | grep -qx input || srun usermod -aG input "$USER"
[ -d "$HOME/.logs" ] || run mkdir -p "$HOME/.logs"
[ -d "$HOME/Pictures" ] || run mkdir -p "$HOME/Pictures"
