#!/usr/bin/env python3
# 20-remote-user — trusts REMOTE_USER on DOMjudge's web UI firewall.
import yaml

path = "/opt/domjudge/domserver/webapp/config/packages/security.yaml"
with open(path) as f:
    security = yaml.safe_load(f)
# Safe only because the host's nginx sets REMOTE_USER from oauth2-proxy and the port binds 127.0.0.1.
security["security"]["firewalls"]["main"]["remote_user"] = {"provider": "domjudge_db_provider"}
# Firewalls match in order: sorting keys would put main (^/) before metrics.
with open(path, "w") as f:
    yaml.safe_dump(security, f, sort_keys=False)
