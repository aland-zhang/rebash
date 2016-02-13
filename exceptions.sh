#!/bin/env bash
source $(dirname ${BASH_SOURCE[0]})/core.sh
core.import logging

exceptions__doc__='
    >>> exceptions_activate
    >>> fail() { return 1; }
    >>> fail
    +doc_test_ellipsis
    Traceback (most recent call first):
    ...

    >>> exceptions_activate
    >>> exceptions.try {
    >>>     false
    >>> } exceptions.catch {
    >>>     echo caught
    >>> }
    caught

    Nested exceptions:
    >>> foo() {
    >>>     true
    >>>     exceptions.try {
    >>>         false
    >>>     } exceptions.catch {
    >>>         echo caught inside foo
    >>>     }
    >>>     false # this is not expected to fail
    >>>     echo this should never be printed
    >>> }
    >>>
    >>> exceptions.try {
    >>>     foo
    >>> } exceptions.catch {
    >>>     echo caught
    >>> }
    >>>
    caught inside foo
    caught

    Exceptions are implicitely active inside try blocks:
    >>> foo() {
    >>>     echo $1
    >>>     true
    >>>     exceptions.try {
    >>>         false
    >>>     } exceptions.catch {
    >>>         echo caught inside foo
    >>>     }
    >>>     false # this is not expected to fail
    >>>     echo this should never be printed
    >>> }
    >>>
    >>> foo "EXCEPTIONS NOT ACTIVE:"
    >>> exceptions_activate
    >>> foo "EXCEPTIONS ACTIVE:"
    +doc_test_ellipsis
    EXCEPTIONS NOT ACTIVE:
    caught inside foo
    this should never be printed
    EXCEPTIONS ACTIVE:
    caught inside foo
    Traceback (most recent call first):
    ...
'
exceptions_active=false
exceptions_active_before_try=false
declare -ig exceptions_try_catch_level=0
exceptions_debug_handler() {
    #echo DEBUG: $(caller) ${BASH_SOURCE[2]}
    printf "# endregion\n"
    printf "# region: %s\n" "$BASH_COMMAND"
}
exceptions_exit_handler() {
    logging.error "EXIT HANDLER"
    #echo DEBUG: $(caller) ${BASH_SOURCE[2]}
}
exceptions_error_handler() {
    local error_code=$?
    (( exceptions_try_catch_level > 0 )) && exit $error_code
    logging.plain "Traceback (most recent call first):"
    local -i i=0
    while caller $i > /dev/null
    do
        local -a trace=( $(caller $i) )
        local line=${trace[0]}
        local subroutine=${trace[1]}
        local filename=${trace[2]}
        logging.plain "[$i] ${filename}:${line}: ${subroutine}"
        ((i++))
    done
    exit $error_code
}
exceptions_deactivate() {
    $exceptions_active || return 0
    [ "$exceptions_errtrace_saved" = "off" ] && set +o errtrace
    [ "$exceptions_pipefail_saved" = "off" ] && set +o pipefail
    export PS4="$exceptions_ps4_saved"
    trap "$exceptions_err_traps" ERR
    exceptions_active=false
}
exceptions_activate() {
    local __doc__='
    '
    $exceptions_active && return 0

    exceptions_errtrace_saved=$(set -o | awk '/errtrace/ {print $2}')
    exceptions_pipefail_saved=$(set -o | awk '/pipefail/ {print $2}')
    exceptions_ps4_saved="$PS4"
    exceptions_err_traps=$(trap -p ERR | cut --delimiter "'" --fields 2)

    # improve xtrace output (set -x)
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

    # If set, any trap on DEBUG and RETURN are inherited by shell functions,
    # command substitutions, and commands executed in a subshell environment.
    # The DEBUG and RETURN traps are normally not inherited in such cases.
    set -o errtrace
    # If set, any trap on ERR is inherited by shell functions,
    # command substitutions, and commands executed in a subshell environment.
    # The ERR trap is normally not inherited in such cases.
    set -o pipefail
    # Treat unset variables and parameters other than the special parameters
    # ‘@’ or ‘*’ as an error when performing parameter expansion.
    # An error message will be written to the standard error, and a
    # non-interactive shell will exit.
    #set -o nounset

    # traps:
    # EXIT      executed on shell exit
    # DEBUG	executed before every simple command
    # RETURN    executed when a shell function or a sourced code finishes executing
    # ERR       executed each time a command's failure would cause the shell to exit when the '-e' option ('errexit') is enabled

    # ERR is not executed in following cases:
    # >>> err() { return 1;}
    # >>> ! err
    # >>> err || echo foo
    # >>> err && echo foo

    trap exceptions_error_handler ERR
    #trap exceptions_debug_handler DEBUG
    #trap exceptions_exit_handler EXIT
    exceptions_active=true
}
exceptions_enter_try() {
    if (( exceptions_try_catch_level == 0 )); then
        exceptions_active_before_try=$exceptions_active
    fi
    exceptions_deactivate
    exceptions_try_catch_level+=1
}
exceptions_exit_try() {
    local exceptions_result=$?
    exceptions_try_catch_level+=-1
    if (( exceptions_try_catch_level > 0 )); then
        exceptions_activate
    else
        $exceptions_active_before_try && exceptions_activate
    fi
    return $exceptions_result
}
alias exceptions.activate="exceptions_activate"
alias exceptions.deactivate="exceptions_deactivate"
alias exceptions.try='exceptions_enter_try; ( exceptions_activate; '
alias exceptions.catch='); exceptions_exit_try $? || '
