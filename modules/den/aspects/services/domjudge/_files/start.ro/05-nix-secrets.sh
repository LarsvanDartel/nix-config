#!/bin/sh -eu
# 05-nix-secrets — seed DOMjudge's credential files from the sops env file.
# The DB keeps whatever the *first* install saw: rotating these in sops later
# does not change the admin/judgehost passwords in the database.
: "${DJ_ADMIN_PASSWORD:?}" "${DJ_JUDGEHOST_PASSWORD:?}"
cd /opt/domjudge/domserver/etc
umask 077
printf '%s\n' "$DJ_ADMIN_PASSWORD" >initial_admin_password.secret
printf 'default\thttp://localhost/api\tjudgehost\t%s\n' "$DJ_JUDGEHOST_PASSWORD" >restapi.secret
