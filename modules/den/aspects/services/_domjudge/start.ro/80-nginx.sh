#!/bin/sh -eu
# 80-nginx — REMOTE_USER from the Remote-User header, and time for large
# problem-zip imports (nginx's 60s default cuts them off mid-transaction).
# shellcheck disable=SC2016 # $remote_user etc. are nginx variables
sed -i 's/^fastcgi_param  *REMOTE_USER  *\$remote_user;$/fastcgi_param REMOTE_USER $http_remote_user;/' /etc/nginx/fastcgi_params
grep -qx 'fastcgi_param REMOTE_USER $http_remote_user;' /etc/nginx/fastcgi_params
echo 'fastcgi_read_timeout 600s;' >>/etc/nginx/snippets/domjudge-inner
