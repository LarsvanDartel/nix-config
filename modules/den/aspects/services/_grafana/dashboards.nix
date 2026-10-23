# Provisioned dashboards, as data: attrset of file name -> dashboard JSON value.
# Hand-written, not imported from grafana.com: id-pulled dashboards are
# unreviewable blobs that break silently when metric names change.
#
# Panels state only their size; `layout` places them on the 24-column grid.
{lib}: let
  inherit (lib) foldl' imap0 length max optionalAttrs;

  prom = {
    type = "prometheus";
    uid = "prometheus";
  };
  loki = {
    type = "loki";
    uid = "loki";
  };

  # Left to right, wrapping when a row is full; rows (w = 24) always wrap.
  layout = panels:
    (foldl' (acc: p: let
        w = p.w or 12;
        h = p.h or 8;
        wrap = acc.x + w > 24;
        x =
          if wrap
          then 0
          else acc.x;
        y =
          if wrap
          then acc.y + acc.rowH
          else acc.y;
      in {
        x = x + w;
        inherit y;
        rowH =
          if wrap
          then h
          else max acc.rowH h;
        out =
          acc.out
          ++ [
            (removeAttrs p ["w" "h"]
              // {
                id = length acc.out + 1;
                gridPos = {inherit x y w h;};
              })
          ];
      }) {
        x = 0;
        y = 0;
        rowH = 0;
        out = [];
      }
      panels)
    .out;

  refIds = ["A" "B" "C" "D" "E" "F"];
  targets = ds:
    imap0 (i: t:
      {
        refId = builtins.elemAt refIds i;
        datasource = ds;
      }
      // t);

  row = title: {
    inherit title;
    type = "row";
    collapsed = false;
    panels = [];
    w = 24;
    h = 1;
  };

  timeseries = {
    title,
    queries,
    unit ? "short",
    ds ? prom,
    w ? 12,
    h ? 8,
    description ? null,
  }:
    {
      inherit title w h;
      type = "timeseries";
      datasource = ds;
      targets = targets ds queries;
      fieldConfig = {
        defaults = {
          inherit unit;
          custom.fillOpacity = 8;
        };
        overrides = [];
      };
    }
    // optionalAttrs (description != null) {inherit description;};

  # One tile per series. `alarm`: "high" is red from 1 up (failures, flags),
  # "low" is red below 1 (up-ness), "none" is an uncoloured reading.
  stat = {
    title,
    queries,
    unit ? "short",
    alarm ? "high",
    w ? 6,
    h ? 4,
    description ? null,
  }:
    {
      inherit title w h;
      type = "stat";
      datasource = prom;
      targets = targets prom queries;
      options = {
        colorMode =
          if alarm == "none"
          then "none"
          else "background";
        graphMode = "none";
        reduceOptions.calcs = ["lastNotNull"];
      };
      fieldConfig = {
        defaults = {
          inherit unit;
          thresholds = {
            mode = "absolute";
            steps = let
              step = color: value: {inherit color value;};
            in
              if alarm == "low"
              then [(step "red" null) (step "green" 1)]
              else [(step "green" null) (step "red" 1)];
          };
        };
        overrides = [];
      };
    }
    // optionalAttrs (description != null) {inherit description;};

  # Instant query rendered as rows; `hide` drops label columns nobody reads.
  table = {
    title,
    expr,
    unit ? "short",
    ds ? prom,
    hide ? [],
    w ? 12,
    h ? 8,
    description ? null,
  }:
    {
      inherit title w h;
      type = "table";
      datasource = ds;
      targets = targets ds [
        (
          if ds == prom
          then {
            inherit expr;
            instant = true;
            format = "table";
          }
          else {
            inherit expr;
            queryType = "instant";
          }
        )
      ];
      fieldConfig = {
        defaults = {inherit unit;};
        overrides = [];
      };
      transformations = [
        {
          id = "organize";
          options.excludeByName = lib.genAttrs (["Time" "__name__" "job"] ++ hide) (_: true);
        }
      ];
    }
    // optionalAttrs (description != null) {inherit description;};

  logs = {
    title,
    expr,
    w ? 24,
    h ? 10,
  }: {
    inherit title w h;
    type = "logs";
    datasource = loki;
    targets = targets loki [{inherit expr;}];
    options = {
      showTime = true;
      wrapLogMessage = true;
      sortOrder = "Descending";
    };
  };

  q = expr: legendFormat: {inherit expr legendFormat;};

  # Every dashboard marks deploys and reboots, so a change in a graph can be
  # read against what changed on the host.
  annotations = [
    {
      name = "Deploys";
      enable = true;
      iconColor = "blue";
      datasource = loki;
      expr = ''{unit="comin.service"} |= "deploying generation"'';
      target = {
        refId = "Anno";
        expr = ''{unit="comin.service"} |= "deploying generation"'';
      };
      titleFormat = "deploy";
      tagKeys = "host";
    }
    {
      name = "Reboots";
      enable = true;
      iconColor = "orange";
      datasource = prom;
      expr = "changes(node_boot_time_seconds[2m]) > 0";
      step = "1m";
      titleFormat = "{{instance}} rebooted";
    }
  ];

  dashboard = {
    title,
    uid,
    panels,
  }: {
    inherit title uid;
    timezone = "browser";
    refresh = "1m";
    schemaVersion = 39;
    time = {
      from = "now-24h";
      to = "now";
    };
    annotations.list = annotations;
    panels = layout panels;
  };

  fsFilter = ''fstype!~"tmpfs|ramfs|overlay"'';
  netFilter = ''device!~"lo|veth.*|br-.*|docker.*|vb-.*|ve-.*"'';

  # Units a dashboard watches by timer and by outcome.
  scheduledTimers = "flake-bump.timer|build-gate.timer|sanoid.timer|firefly-auto-import.timer|crowdsec-update-hub.timer|restic-backups-.*";
  scheduledServices = "flake-bump.service|build-gate.service|sanoid.service|firefly-auto-import.service|crowdsec-update-hub.service|restic-backups-.*";
in {
  "fleet.json" = dashboard {
    title = "Fleet";
    uid = "fleet";
    panels = [
      (row "Hosts")
      (timeseries {
        title = "CPU busy";
        unit = "percent";
        queries = [(q ''100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'' "{{instance}}")];
      })
      (timeseries {
        title = "Memory used";
        unit = "percent";
        queries = [(q "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100)" "{{instance}}")];
      })
      (timeseries {
        title = "CPU iowait and steal";
        unit = "percent";
        description = "Steal is gaia's hypervisor taking CPU back; iowait is endeavour's disks.";
        queries = [(q ''avg by (instance, mode) (rate(node_cpu_seconds_total{mode=~"iowait|steal"}[5m])) * 100'' "{{instance}} {{mode}}")];
      })
      (timeseries {
        title = "Pressure stalls";
        unit = "percentunit";
        description = "Share of time some task waited on CPU, IO or memory: contention, not just load.";
        queries = [
          (q "rate(node_pressure_cpu_waiting_seconds_total[5m])" "{{instance}} cpu")
          (q "rate(node_pressure_io_stalled_seconds_total[5m])" "{{instance}} io")
          (q "rate(node_pressure_memory_stalled_seconds_total[5m])" "{{instance}} memory")
        ];
      })
      (timeseries {
        title = "Memory: used vs ZFS ARC";
        unit = "bytes";
        description = "ARC counts as used but gives memory back under pressure.";
        queries = [
          (q "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes" "{{instance}} used")
          (q "node_zfs_arc_size" "{{instance}} ARC")
        ];
      })
      (timeseries {
        title = "Network";
        unit = "bps";
        queries = [
          (q "sum by (instance, device) (rate(node_network_receive_bytes_total{${netFilter}}[5m])) * 8" "{{instance}} {{device}} in")
          (q "-sum by (instance, device) (rate(node_network_transmit_bytes_total{${netFilter}}[5m])) * 8" "{{instance}} {{device}} out")
        ];
      })
      (timeseries {
        title = "Conntrack table";
        unit = "percentunit";
        description = "A full table drops new connections silently; gaia is the edge.";
        w = 8;
        queries = [(q "node_nf_conntrack_entries / node_nf_conntrack_entries_limit" "{{instance}}")];
      })
      (timeseries {
        title = "Hottest sensor";
        unit = "celsius";
        w = 8;
        queries = [(q "max by (instance) (node_hwmon_temp_celsius)" "{{instance}}")];
      })
      (timeseries {
        title = "Established TCP";
        w = 8;
        queries = [(q "node_netstat_Tcp_CurrEstab" "{{instance}}")];
      })

      (row "Storage")
      (timeseries {
        title = "Filesystem used";
        unit = "percent";
        queries = [(q "100 - (node_filesystem_avail_bytes{${fsFilter}} / node_filesystem_size_bytes * 100)" "{{instance}} {{mountpoint}}")];
      })
      (table {
        title = "Days until full";
        unit = "d";
        description = "Filesystems shrinking over the last day, extrapolated. Absent means not filling.";
        hide = ["device" "fstype"];
        expr = "(node_filesystem_avail_bytes{${fsFilter}} / (-deriv(node_filesystem_avail_bytes{${fsFilter}}[1d]) > 0)) / 86400";
      })
      (timeseries {
        title = "ZFS ARC hit ratio";
        unit = "percentunit";
        queries = [(q "rate(node_zfs_arc_hits[5m]) / (rate(node_zfs_arc_hits[5m]) + rate(node_zfs_arc_misses[5m]))" "{{instance}}")];
      })
      (timeseries {
        title = "ZFS ARC size";
        unit = "bytes";
        queries = [
          (q "node_zfs_arc_size" "{{instance}} size")
          (q "node_zfs_arc_c_max" "{{instance}} max")
        ];
      })

      (row "Services")
      (timeseries {
        title = "Failed units";
        queries = [(q ''sum by (instance) (node_systemd_unit_state{state="failed"})'' "{{instance}}")];
      })
      (table {
        title = "Failed now";
        hide = ["state" "type"];
        expr = ''node_systemd_unit_state{state="failed"} == 1'';
      })
      (timeseries {
        title = "Errors logged, by unit";
        ds = loki;
        description = "Journal lines at error or worse. A climbing line is a unit crash-looping before it hits its start limit.";
        queries = [(q ''topk(10, sum by (host, unit) (count_over_time({job="systemd-journal", level=~"error|crit|alert|emerg"} [5m])))'' "{{host}} {{unit}}")];
      })
      (stat {
        title = "Scrape targets down";
        description = "A dead exporter otherwise just reads as a flat line.";
        queries = [(q "count(up == 0) or vector(0)" "down")];
      })
      (table {
        title = "Down targets";
        w = 6;
        h = 4;
        expr = "up == 0";
      })
    ];
  };

  "pipeline.json" = dashboard {
    title = "Deploy pipeline";
    uid = "pipeline";
    panels = [
      (row "What runs where")
      (table {
        title = "Deployed commit";
        description = "comin's view; the deploy branch is what build-gate let through.";
        hide = ["Value"];
        expr = "comin_deployment_info";
      })
      (stat {
        title = "comin failures";
        w = 8;
        queries = [
          (q "max by (instance) (comin_last_fetch_failed)" "{{instance}} fetch")
          (q "max by (instance) (comin_last_eval_failed)" "{{instance}} eval")
          (q "max by (instance) (comin_last_build_failed)" "{{instance}} build")
          (q "max by (instance) (comin_last_deployment_failed)" "{{instance}} deploy")
        ];
      })
      (stat {
        title = "Reboot pending";
        description = "The deployed generation's kernel or initrd differs from the booted one.";
        w = 4;
        queries = [(q "comin_need_to_reboot" "{{instance}}")];
      })

      (row "Scheduled work")
      (table {
        title = "Since last run";
        unit = "s";
        description = "Timer last fired. Read with the next panel: firing is not succeeding.";
        expr = ''time() - node_systemd_timer_last_trigger_seconds{name=~"${scheduledTimers}"}'';
      })
      (table {
        title = "Failed now (1 = failed)";
        hide = ["state" "type"];
        description = "flake-bump sat here for six days before 2026-10-21.";
        expr = ''node_systemd_unit_state{state="failed", name=~"${scheduledServices}"}'';
      })
      (timeseries {
        title = "Gate and bump outcomes";
        ds = loki;
        w = 24;
        queries = [
          (q ''sum by (unit) (count_over_time({unit=~"build-gate.service|flake-bump.service"} |= "build failed for" [1h]))'' "{{unit}} failed")
          (q ''sum(count_over_time({unit="build-gate.service"} |= "green" [1h]))'' "build-gate green")
          (q ''sum(count_over_time({unit="flake-bump.service"} |= "pushed" [1h]))'' "flake-bump pushed")
        ];
      })
      (logs {
        title = "build-gate and flake-bump";
        expr = ''{unit=~"build-gate.service|flake-bump.service"} |~ "^verifying|green|build failed for|reverting the lock|pushed|lock unchanged|nothing to verify"'';
      })
      (logs {
        title = "comin";
        h = 8;
        expr = ''{unit="comin.service"} |~ "deploying generation|level=error"'';
      })
    ];
  };

  "edge.json" = dashboard {
    title = "Edge and security";
    uid = "edge";
    panels = [
      (row "Published services (gatus, from outside)")
      (timeseries {
        title = "Probe success";
        queries = [(q "gatus_results_endpoint_success" "{{name}}")];
      })
      (table {
        title = "Uptime, 24h";
        unit = "percentunit";
        hide = ["group" "key" "type"];
        expr = "avg_over_time(gatus_results_endpoint_success[24h])";
      })
      (timeseries {
        title = "Response time";
        unit = "s";
        queries = [(q "gatus_results_duration_seconds" "{{name}}")];
      })
      (table {
        title = "Certificate days left";
        unit = "d";
        hide = ["group" "key" "type"];
        expr = "gatus_results_certificate_expiration_seconds / 86400";
      })

      (row "NetBird")
      (timeseries {
        title = "Connected peers";
        w = 8;
        queries = [(q "management_grpc_connected_streams_ratio" "peers")];
      })
      (timeseries {
        title = "Proxy connections";
        w = 8;
        queries = [(q "management_proxy_connection_count" "netbird-proxy")];
      })
      (timeseries {
        title = "Peer logins";
        unit = "reqps";
        w = 8;
        queries = [(q "sum(rate(management_grpc_login_request_counter_total[5m]))" "logins")];
      })

      (row "crowdsec")
      (timeseries {
        title = "Active decisions, by origin";
        queries = [(q "sum by (origin) (cs_active_decisions)" "{{origin}}")];
      })
      (timeseries {
        title = "Alerts, by scenario";
        queries = [(q "sum by (reason) (cs_alerts)" "{{reason}}")];
      })
      (timeseries {
        title = "Firewall drops";
        unit = "pps";
        queries = [(q "sum by (origin) (rate(fw_bouncer_dropped_packets[5m]))" "{{origin}}")];
      })
      (timeseries {
        title = "Lines read, by source";
        unit = "short";
        description = "endeavour's nginx line is the remote agent; flat at zero means it stopped reading.";
        queries = [
          (q "sum by (instance, source) (rate(cs_filesource_hits_total[5m]))" "{{instance}} {{source}}")
          (q "sum by (instance, source) (rate(cs_journalctlsource_hits_total[5m]))" "{{instance}} {{source}}")
        ];
      })
      (timeseries {
        title = "Parsed vs unparsed";
        queries = [
          (q "sum by (instance) (rate(cs_parser_hits_ok_total[5m]))" "{{instance}} ok")
          (q "sum by (instance) (rate(cs_parser_hits_ko_total[5m]))" "{{instance}} unparsed")
        ];
      })
      (timeseries {
        title = "Agent requests to the LAPI";
        description = "Per machine: a remote agent that falls to zero has lost its LAPI.";
        queries = [(q "sum by (machine) (rate(cs_lapi_machine_requests_total[5m]))" "{{machine}}")];
      })

      (row "Logins")
      (timeseries {
        title = "gaia SSH failures";
        ds = loki;
        queries = [(q ''sum(count_over_time({host="gaia", unit="sshd.service"} |~ "Invalid user|Failed password|authentication failure" [15m]))'' "failures / 15m")];
      })
      (timeseries {
        title = "kanidm logins";
        ds = loki;
        description = "Attempts verified against the log; the denial wording is assumed until a failed login is seen.";
        queries = [
          (q ''sum(count_over_time({unit="kanidm.service"} |= "Request credential continuation" [1h]))'' "attempts")
          (q ''sum(count_over_time({unit="kanidm.service"} |~ "(?i)credentials? denied" [1h]))'' "denied")
        ];
      })

      (row "nginx")
      (timeseries {
        title = "Requests, by status class";
        ds = loki;
        queries = [(q ''sum by (host, status) (count_over_time({job="nginx", log="access"} | regexp "\" (?P<status>[0-9])[0-9]{2} " [5m]))'' "{{host}} {{status}}xx")];
      })
      (table {
        title = "Top external clients, endeavour nginx, 24h";
        ds = loki;
        description = "Only firefly, bin and packs pass endeavour's nginx; every other published app is proxied straight to its port. Loopback (the *arr stack) and Gatus are filtered out.";
        expr = ''topk(10, sum by (ip) (count_over_time({job="nginx", log="access", host="endeavour"} !~ "Gatus/" | regexp "^(?P<ip>\\S+) " | ip !~ "127\\.0\\.0\\.1|::1" [24h])))'';
      })
      (timeseries {
        title = "Refused by access rule";
        ds = loki;
        description = "minecraft-control refusing netbird-proxy: its mesh address has moved again.";
        w = 8;
        queries = [(q ''sum by (host) (count_over_time({job="nginx", log="error"} |= "access forbidden by rule" [15m]))'' "{{host}}")];
      })
      (timeseries {
        title = "Firefly /api/ multipart refused";
        ds = loki;
        description = "PHP2Shell-shaped requests stopped at nginx before PHP.";
        w = 8;
        queries = [(q ''sum(count_over_time({job="nginx", log="access", host="endeavour"} |~ "\"POST /api/" |~ "\" 403 " [15m]))'' "refused")];
      })
      (timeseries {
        title = "5xx";
        ds = loki;
        w = 8;
        queries = [(q ''sum by (host) (count_over_time({job="nginx", log="access"} |~ "\" 5[0-9]{2} " [5m]))'' "{{host}}")];
      })
    ];
  };

  "hardware.json" = dashboard {
    title = "endeavour hardware";
    uid = "hardware";
    panels = [
      (timeseries {
        title = "Temperatures (BMC)";
        unit = "celsius";
        # Both CPU sensors are named "Temp"; the id tells them apart.
        queries = [(q "ipmi_temperature_celsius" "{{name}} {{id}}")];
      })
      (timeseries {
        title = "Fans";
        unit = "rotrpm";
        description = "Pinned high and flat is the fan controller dead with the BMC left in manual mode (2026-10-21).";
        queries = [(q "ipmi_fan_speed_rpm" "{{name}}")];
      })
      (timeseries {
        title = "Fan controller target";
        unit = "percent";
        ds = loki;
        queries = [(q ''avg by (host) (avg_over_time({unit="ipmi-fan-control.service"} | regexp "setting fan speed to (?P<speed>[0-9]+)%" | unwrap speed [5m]))'' "target")];
      })
      (timeseries {
        title = "Power draw";
        unit = "watt";
        queries = [
          (q "ipmi_dcmi_power_consumption_watts" "system (DCMI)")
          (q "ipmi_power_watts" "{{name}}")
        ];
      })
      (stat {
        title = "Energy, last 24h";
        unit = "kwatth";
        alarm = "none";
        queries = [(q "avg_over_time(ipmi_dcmi_power_consumption_watts[24h]) * 24 / 1000" "kWh")];
      })
      (stat {
        title = "BMC collectors up";
        alarm = "low";
        description = "0 is a collector failing to read the BMC.";
        w = 18;
        queries = [(q "ipmi_up" "{{collector}}")];
      })
    ];
  };
}
