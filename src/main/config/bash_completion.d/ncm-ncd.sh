# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}
#

_ncm_ncd_ccm_bashcompletion_fn=/etc/bash_completion.d/quattor-ccm
if [[ -z "$_quattor_ccm_CLI_longoptions" && -f $_ncm_ncd_ccm_bashcompletion_fn ]]; then
    source $_ncm_ncd_ccm_bashcompletion_fn
fi
unset _ncm_ncd_ccm_bashcompletion_fn

_quattor_ncm_ncd_default_options=(debug help quiet verbose version)

_quattor_ncm_ncd_options=(all allowbrokencomps autodeps cache_root cfgfile check-noquattor chroot configure facility force-quattor forcelock history history-instances ignore-errors-from-dependencies ignorelock include list log_group_readable log_world_readable logdir logpid multilog noaction nodeps post-hook post-hook-timeout pre-hook pre-hook-timeout report report-format retries skip state timeout unconfigure useprofile verbose_logfile)

# boolean options which are true by default
_quattor_ncm_ncd_no_options=(no-autodeps no-check-noquattor)

_quattor_ncm_ncd_longoptions=`_quattor_ccm_make_long_options ${_quattor_ncm_ncd_options[@]} ${_quattor_ncm_ncd_no_options[@]} ${_quattor_ncm_ncd_default_options[@]}`

_quattor_ncm_ncd_report_formats=(nagios simple)

_ncm_ncd()
{
    local cur prev

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --cache_root|--logdir)
            COMPREPLY=( $(compgen -d ${cur}) )
            return 0
            ;;
        --cfgfile)
            COMPREPLY=( $(compgen -f ${cur}) )
            return 0
            ;;
        --useprofile)
            _quattor_ccm_tabcomp_cids
            return 0
            ;;
        --report-format)
            # use [*] here, value for -W has to be single string
            COMPREPLY=($(compgen -W "${_quattor_ncm_ncd_report_formats[*]}" -- ${cur}))
            return 0
            ;;
        *)
            case "$cur" in
                -*)
                    COMPREPLY=($(compgen -W "$_quattor_ncm_ncd_longoptions" -- ${cur}))
                    ;;
                *)
                    # No option or component to handle: show any component
                    # _quattor_ccm_tabcomp_components sets COMPREPLY
                    _quattor_ccm_tabcomp_components
                    # uncomment this is we should show all components and all options
                    #COMPREPLY=($(compgen -W "${COMPREPLY[@]} $_quattor_ncm_ncd_longoptions" -- ${cur}))
                    ;;
            esac
    esac

    return 0
}

complete -F _ncm_ncd ncm-ncd
complete -F _ncm_ncd quattor-configure
complete -F _ncm_ncd quattor-list
complete -F _ncm_ncd quattor-unconfigure
