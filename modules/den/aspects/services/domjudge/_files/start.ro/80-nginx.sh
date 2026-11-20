#!/bin/sh -eu
# 80-nginx — takes REMOTE_USER from the Remote-User header and allows slow problem-zip imports.
# shellcheck disable=SC2016 # $remote_user etc. are nginx variables
sed -i 's/^fastcgi_param  *REMOTE_USER  *\$remote_user;$/fastcgi_param REMOTE_USER $http_remote_user;/' /etc/nginx/fastcgi_params
grep -qx 'fastcgi_param REMOTE_USER $http_remote_user;' /etc/nginx/fastcgi_params
# nginx's 60s default cuts large problem-zip imports off mid-transaction.
echo 'fastcgi_read_timeout 600s;' >>/etc/nginx/snippets/domjudge-inner
