# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#
# Bash autocompletion script for ncm-ncd.  Autocompletes component
# names and common options.  Based on the Debian tutorial "An
# introduction to bash completion":
#
# http://www.debian-administration.org/article/316/An_introduction_to_bash_completion_part_1
# http://www.debian-administration.org/article/317/An_introduction_to_bash_completion_part_2
#

# If the option under completion starts with a dash, autocompletes an
# option name (i.e, "--configure").  Otherwise, autocompletes a
# component name.
_ncm_ncd()
{
    local opts="--all --allowbrokencomps --autodeps --cache_root --cfgfile --check-noquattor --chroot --configure --facility --forcelock --history --history-instances --ignore-errors-from-dependencies --ignorelock --include --list --logdir --multilog --noaction --nodeps --post-hook --post-hook-timeout --pre-hook --pre-hook-timeout --retries --skip --state --template-path --timeout --unconfigure --useprofile"
    local comps=`find /usr/lib/perl/NCM/Component -maxdepth 1 -name '*.pm' -exec basename '{}' .pm ';'`
    COMPREPLY=()
    local cur="${COMP_WORDS[COMP_CWORD]}"
    case $cur in
        -*)
            COMPREPLY=($(compgen -W "$opts" -- ${cur}))
            return 0
            ;;
        *)
            COMPREPLY=($(compgen -W "$comps" -- ${cur}))
            return 0
            ;;
    esac
}

complete -F _ncm_ncd ncm-ncd
complete -F _ncm_ncd quattor-configure
complete -F _ncm_ncd quattor-list
complete -F _ncm-ncd quattor-unconfigure
