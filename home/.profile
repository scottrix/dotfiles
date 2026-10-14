export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export EDITOR=vim
case ":$PATH:" in
    *":$HOME/bin:"*) ;;
    *) PATH="$HOME/bin:$HOME/.local/bin:$PATH" ;;
esac
[ -f ~/.gpgagentrc ] && . ~/.gpgagentrc
