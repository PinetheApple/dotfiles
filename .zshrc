# enable colors and change prompt
autoload -U colors && colors
PS1="%B%{$fg[blue]%}%n%{$fg[green]%}@%{$fg[green]%}%M:%{$fg[red]%}%~%{$reset_color%}$%b "

# enable color support for commands
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -l'
alias la='ls -A'
#alias l='ls -CF'

# terminal history
HISTFILE=~/.cache/zsh/.histfile
HISTSIZE=3000
SAVEHIST=1000

bindkey -e

# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/pineapple/.zshrc'

autoload -Uz compinit
compinit

# add aliases
[ -f "$HOME/.config/.zsh_aliases" ] && source "$HOME/.config/.zsh_aliases"

# load zsh-syntax-highlighting; should be at the end of the file
if [ -f "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then 
	source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null
fi
