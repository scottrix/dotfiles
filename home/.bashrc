# ~/.bashrc from github.com/scottrix/dotfiles. Put machine-only additions in ~/.bashrc.local.
[[ $- != *i* ]] && return

export HISTCONTROL=ignoreboth,erasedups
PS1='[\u@\h \W]\$ '

# pinentry for gpg (mail passwords, SSH keys) in this terminal
GPG_TTY=$(tty)
export GPG_TTY
[ -f ~/.gpgagentrc ] && . ~/.gpgagentrc

# podman stands in for docker
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock

[ -f ~/.bashrc.local ] && . ~/.bashrc.local
