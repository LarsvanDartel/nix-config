#!/bin/sh -eu
# 05-nix-secrets — seeds DOMjudge's credential files from the sops env file.
: "${DJ_ADMIN_PASSWORD:?}" "${DJ_JUDGEHOST_PASSWORD:?}"
cd /opt/domjudge/domserver/etc
umask 077
# Only the first install reads these: rotating them in sops leaves the DB's passwords unchanged.
printf '%s\n' "$DJ_ADMIN_PASSWORD" >initial_admin_password.secret
printf 'default\thttp://localhost/api\tjudgehost\t%s\n' "$DJ_JUDGEHOST_PASSWORD" >restapi.secret
