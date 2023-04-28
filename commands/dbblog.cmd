#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${WARDEN_DB:-1} -eq 0 ]]; then
  fatal "Database environment is not used (WARDEN_DB=0)."
fi

if (( ${#WARDEN_PARAMS[@]} == 0 )) || [[ "${WARDEN_PARAMS[0]}" == "help" ]]; then
  $WARDEN_BIN dbblog --help || exit $? && exit $?
fi

## load connection information for the mysql service
DBBLOG_CONTAINER=$($WARDEN_BIN env ps -q dbblog)
if [[ ! ${DBBLOG_CONTAINER} ]]; then
    fatal "No container found for dbblog service."
fi

eval "$(
    docker container inspect ${DBBLOG_CONTAINER} --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^MYSQLBLOG_"
)"

## sub-command execution
case "${WARDEN_PARAMS[0]}" in
    connect)
        "$WARDEN_BIN" env exec dbblog \
            mysql -u"${MYSQLBLOG_USER}" -p"${MYSQLBLOG_PASSWORD}" --database="${MYSQLBLOG_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    import)
        LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`/DEFINER=CURRENT_USER/g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | "$WARDEN_BIN" env exec -T dbblog \
            mysql -u"${MYSQLBLOG_USER}" -p"${MYSQLBLOG_PASSWORD}" --database="${MYSQLBLOG_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    dump)
            "$WARDEN_BIN" env exec -T dbblog \
            mysqldump -u"${MYSQLBLOG_USER}" -p"${MYSQLBLOG_PASSWORD}" "${MYSQLBLOG_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    *)
        fatal "The command \"${WARDEN_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
