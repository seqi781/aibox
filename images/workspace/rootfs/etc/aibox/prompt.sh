# aibox 提示符：固定以 [aibox] 开头，一眼区分容器和宿主机
__aibox_ps1_git() { local b; b=$(git symbolic-ref --short HEAD 2>/dev/null) && printf ' (%s)' "$b"; }
PS1='\[\e[35m\][aibox]\[\e[0m\] \[\e[34m\]\w\[\e[33m\]$(__aibox_ps1_git)\[\e[0m\]\$ '
