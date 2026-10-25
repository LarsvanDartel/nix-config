#!/usr/bin/env python3
# 20-remote-user — trust REMOTE_USER on the web UI firewall. Set by the host's
# nginx from oauth2-proxy; the container port is bound to 127.0.0.1 only.
import yaml

path = "/opt/domjudge/domserver/webapp/config/packages/security.yaml"
with open(path) as f:
    security = yaml.safe_load(f)
security["security"]["firewalls"]["main"]["remote_user"] = {"provider": "domjudge_db_provider"}
# Firewalls match in order: sorting keys would put main (^/) before metrics.
with open(path, "w") as f:
    yaml.safe_dump(security, f, sort_keys=False)
