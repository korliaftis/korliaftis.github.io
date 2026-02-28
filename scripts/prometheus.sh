#!/bin/bash

# This script installs Prometheus on Debian based systems.

set -e
set -u
set -o pipefail

### preflight checks

# failure indicator
PREFLIGHT_CHECKS_FAIL=false

# user check
if [ "${EUID}" -ne 0 ]; then
    PREFLIGHT_CHECKS_FAIL=true
    echo -e "\033[0;91mERROR:\033[0m not running as root"
fi

# dependency check
PACKAGES=("curl" "jq")

for i in "${PACKAGES[@]}"; do
    if ! command -v "${i}" >/dev/null 2>&1; then
        PREFLIGHT_CHECKS_FAIL=true
        echo -e "\033[0;91mERROR:\033[0m ${i} is not installed"
    fi
done

# failure indicator check
if [ "${PREFLIGHT_CHECKS_FAIL}" = true ]; then
    exit 1
fi

### variables

# script variables
TEMP_DIR="$(mktemp -d)"
SYSTEM_ARCH="$(dpkg --print-architecture)"

# app variables
APP_SA="prometheus"
APP_VERSION="$(curl -Ls https://api.github.com/repos/prometheus/prometheus/releases/latest | jq -r .tag_name)"

# app upgrade variables
APP_UPGRADE=false
if [ -f /usr/local/bin/prometheus ]; then
    APP_UPGRADE=true
fi

### download

# status message
echo -e "\033[0;92mINFO:\033[0m downloading prometheus ${APP_VERSION} for ${SYSTEM_ARCH} architecture"

# download binaries
curl -sLo ${TEMP_DIR}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz https://github.com/prometheus/prometheus/releases/download/${APP_VERSION}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz
tar -xzf ${TEMP_DIR}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}.tar.gz --directory ${TEMP_DIR}

### upgrade

if [ "${APP_UPGRADE}" = true ]; then
    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrading the existing installation"

    # stop service
    systemctl --quiet stop prometheus.service

    # copy binaries
    install -m 0755 -o ${APP_SA} -g ${APP_SA} ${TEMP_DIR}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/prometheus /usr/local/bin/prometheus
    install -m 0755 -o ${APP_SA} -g ${APP_SA} ${TEMP_DIR}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/promtool /usr/local/bin/promtool

    # start service
    systemctl --quiet start prometheus.service

    # status message
    echo -e "\033[0;92mINFO:\033[0m upgrade succeeded"

    exit 0
fi

### install

# status message
echo -e "\033[0;92mINFO:\033[0m starting the installation"

# create service account
useradd --system --no-create-home --shell /bin/false ${APP_SA}

# create directories
mkdir /etc/prometheus
mkdir /etc/prometheus/rules
mkdir /etc/prometheus/targets
mkdir /etc/prometheus/targets/servers
mkdir /etc/prometheus/targets/services
mkdir /etc/prometheus/targets/sites
mkdir /var/lib/prometheus

# create configuration file
cat << 'EOF' > /etc/prometheus/prometheus.yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - 127.0.0.1:9093

rule_files:
- /etc/prometheus/rules/*.yml
- /etc/prometheus/rules/*.yaml

scrape_configs:
- job_name: servers
  metrics_path: /metrics
  file_sd_configs:
  - files:
    - /etc/prometheus/targets/servers/*.yml
    - /etc/prometheus/targets/servers/*.yaml
    - /etc/prometheus/targets/servers/*.json
- job_name: services
  metrics_path: /metrics
  file_sd_configs:
  - files:
    - /etc/prometheus/targets/services/*.yml
    - /etc/prometheus/targets/services/*.yaml
    - /etc/prometheus/targets/services/*.json
- job_name: sites
  metrics_path: /probe
  params:
    module: [http_2xx]
  file_sd_configs:
  - files:
    - /etc/prometheus/targets/sites/*.yml
    - /etc/prometheus/targets/sites/*.yaml
    - /etc/prometheus/targets/sites/*.json
  relabel_configs:
  - source_labels: [__address__]
    target_label: __param_target
  - source_labels: [__param_target]
    target_label: instance
  - target_label: __address__
    replacement: 127.0.0.1:9115
EOF

# create rule files
cat << 'EOF' > /etc/prometheus/rules/alertmanager.yaml
groups:
- name: alertmanager
  rules:

  - alert: alertmanager_configuration_reload_failure
    expr: 'alertmanager_config_last_reload_successful != 1'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "Alertmanager configuration reload failure"
      description: "Alertmanager failed to reload the configuration."

  - alert: alertmanager_too_many_restarts
    expr: 'changes(process_start_time_seconds{job="alertmanager"}[15m]) > 2'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "Alertmanager too many restarts"
      description: "Alertmanager has restarted more than twice in the last 15 minutes."

  - alert: alertmanager_notifications_failing
    expr: 'rate(alertmanager_notifications_failed_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Alertmanager notifications failing"
      description: "Alertmanager is failing to send notifications."
EOF

cat << 'EOF' > /etc/prometheus/rules/blackbox_exporter.yaml
groups:
- name: blackbox_exporter
  rules:

    - alert: blackbox_exporter_configuration_reload_failure
      expr: 'blackbox_exporter_config_last_reload_successful != 1'
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: "Blackbox Exporter configuration reload failure"
        description: "The Blackbox Exporter failed to reload the configuration."

    - alert: blackbox_exporter_too_many_restarts
      expr: 'changes(process_start_time_seconds{job="blackbox_exporter"}[15m]) > 2'
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: "Blackbox Exporter too many restarts"
        description: "The Blackbox Exporter has restarted more than twice in the last 15 minutes."

    - alert: blackbox_exporter_probe_failed
      expr: 'probe_success == 0'
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Blackbox Exporter probe failed"
        description: "A Blackbox Exporter probe has failed, indicating that the monitored service is either unreachable or experiencing issues."

    - alert: blackbox_exporter_probe_http_failure
      expr: 'probe_http_status_code <= 199 OR probe_http_status_code >= 400'
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Blackbox Exporter probe HTTP failure"
        description: "The HTTP status code returned by the Blackbox Exporter probe is outside the 200-399 range, which indicates a failure."

    - alert: blackbox_exporter_ssl_certificate_expiration_7_days
      expr: '3 <= round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 7'
      for: 0m
      labels:
        severity: warning
      annotations:
        summary: "Blackbox Exporter SSL certificate will expire soon"
        description: "The SSL certificate is set to expire in less than 7 days."

    - alert: blackbox_exporter_ssl_certificate_expiration_3_days
      expr: '0 <= round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 3'
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Blackbox Exporter SSL certificate will expire soon"
        description: "The SSL certificate is set to expire in less than 3 days."

    - alert: blackbox_exporter_ssl_certificate_expired
      expr: 'round((last_over_time(probe_ssl_earliest_cert_expiry[10m]) - time()) / 86400, 0.1) < 0'
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Blackbox Exporter SSL certificate expired"
        description: "The SSL certificate has expired."
EOF

cat << 'EOF' > /etc/prometheus/rules/node_exporter.yaml
groups:
- name: node_exporter
  rules:

  - alert: node_exporter_cpu_load_high
    expr: '(sum by (instance) (avg by (mode, instance) (rate(node_cpu_seconds_total{mode!="idle"}[2m]))) > 0.8) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "High CPU load detected"
      description: "The CPU load on \"{{ $labels.instance }}\" has exceeded 80% for the past 10 minutes, indicating high overall CPU utilization, which could affect application performance."

  - alert: node_exporter_cpu_steal_high
    expr: '(avg by(instance) (rate(node_cpu_seconds_total{mode="steal"}[5m])) * 100 > 10) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "High CPU steal detected"
      description: "The CPU steal time on \"{{ $labels.instance }}\" has exceeded 10%, which may indicate performance degradation due to other virtual machines consuming CPU resources on the same host."

  - alert: node_exporter_cpu_iowait_high
    expr: '(avg by (instance) (rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100 > 10) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "High CPU I/O wait detected"
      description: "The CPU I/O wait time on \"{{ $labels.instance }}\" has exceeded 10%, indicating potential disk or network bottlenecks affecting CPU performance."

  - alert: node_exporter_memory_available_low
    expr: '(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Low available memory detected"
      description: "The available memory on \"{{ $labels.instance }}\" is less than 10% for the past 2 minutes, indicating high memory usage that could lead to performance issues."

  - alert: node_exporter_memory_pressure_high
    expr: '(rate(node_vmstat_pgmajfault[1m]) > 1000) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High memory pressure detected"
      description: "The rate of major page faults on \"{{ $labels.instance }}\" has exceeded 1000 per minute, indicating high memory pressure and potential swapping or memory thrashing."

  - alert: node_exporter_swap_usage_high
    expr: '((1 - (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes)) * 100 > 80) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High swap usage detected"
      description: "Swap usage on \"{{ $labels.instance }}\" has exceeded 80%, indicating memory pressure or inefficient memory utilization, which could lead to degraded system performance."

  - alert: node_exporter_oom_kill_detected
    expr: '(increase(node_vmstat_oom_kill[1m]) > 0) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "OOM kill detected"
      description: "An Out of Memory (OOM) kill event has been detected on \"{{ $labels.instance }}\", indicating that the operating system terminated one or more processes to free up memory."

  - alert: node_exporter_disk_space_low
    expr: '((node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes < 10 and ON (instance, device, mountpoint) node_filesystem_readonly == 0) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Low disk space detected"
      description: "The available disk space on \"{{ $labels.device }}\" at \"{{ $labels.mountpoint }}\" on \"{{ $labels.instance }}\" has fallen below 10%, which could impact system performance."

  - alert: node_exporter_disk_inodes_low
    expr: '(node_filesystem_files_free{fstype!="msdosfs"} / node_filesystem_files{fstype!="msdosfs"} * 100 < 10 and ON (instance, device, mountpoint) node_filesystem_readonly == 0) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Low disk inodes detected"
      description: "The available inodes on \"{{ $labels.device }}\" at \"{{ $labels.mountpoint }}\" on \"{{ $labels.instance }}\" have fallen below 10%."

  - alert: node_exporter_filesystem_error
    expr: 'node_filesystem_device_error == 1'
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Filesystem error detected"
      description: "A filesystem error has been detected on \"{{ $labels.instance }}\" with the \"{{ $labels.mountpoint }}\" filesystem."

  - alert: node_exporter_network_receive_errors
    expr: '(rate(node_network_receive_errs_total[2m]) / rate(node_network_receive_packets_total[2m]) > 0.01) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Network receive errors detected"
      description: "Network receive errors have been detected on the \"{{ $labels.device }}\" interface of \"{{ $labels.instance }}\", which may indicate problems with network connectivity or hardware."

  - alert: node_exporter_network_transmit_errors
    expr: '(rate(node_network_transmit_errs_total[2m]) / rate(node_network_transmit_packets_total[2m]) > 0.01) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Network transmit errors detected"
      description: "Network transmit errors have been detected on the \"{{ $labels.device }}\" interface of \"{{ $labels.instance }}\", which may indicate problems with network connectivity or hardware."

  - alert: node_exporter_network_interface_saturated
    expr: '((rate(node_network_receive_bytes_total{device!~"^tap.*|^vnet.*|^veth.*|^tun.*"}[1m]) + rate(node_network_transmit_bytes_total{device!~"^tap.*|^vnet.*|^veth.*|^tun.*"}[1m])) / node_network_speed_bytes{device!~"^tap.*|^vnet.*|^veth.*|^tun.*"} > 0.8 < 10000) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "Network interface saturation detected"
      description: "The network interface \"{{ $labels.device }}\" on \"{{ $labels.instance }}\" is approaching saturation, which could result in network congestion."

  - alert: node_exporter_network_conntrack_entries_high
    expr: '(node_nf_conntrack_entries / node_nf_conntrack_entries_limit > 0.8) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High number of conntrack entries detected"
      description: "The number of conntrack entries on \"{{ $labels.instance }}\" is approaching the limit."

  - alert: node_exporter_hardware_temp_high
    expr: '((node_hwmon_temp_celsius * ignoring(label) group_left(instance, job, node, sensor) node_hwmon_sensor_label{label!="tctl"} > 75)) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High temperature detected"
      description: "A hardware component on \"{{ $labels.instance }}\" has exceeded the temperature threshold, which could result in thermal throttling or hardware damage."

  - alert: node_exporter_hardware_temp_alarm
    expr: '((node_hwmon_temp_crit_alarm_celsius == 1) or (node_hwmon_temp_alarm == 1)) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Temperature alarm detected"
      description: "A temperature alarm has been triggered for the \"{{ $labels.instance }}\" instance."

  - alert: node_exporter_time_offset_detected
    expr: '((node_timex_offset_seconds > 0.05 and deriv(node_timex_offset_seconds[5m]) >= 0) or (node_timex_offset_seconds < -0.05 and deriv(node_timex_offset_seconds[5m]) <= 0)) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Time offset detected"
      description: "A time offset has been detected on \"{{ $labels.instance }}\", suggesting an issue with NTP synchronization on the host."

  - alert: node_exporter_time_not_synchronising
    expr: '(min_over_time(node_timex_sync_status[1m]) == 0 and node_timex_maxerror_seconds >= 16) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Time not synchronising"
      description: "Time is not synchronising on \"{{ $labels.instance }}\", indicating that NTP is not configured correctly on the host."

  - alert: node_exporter_reboot_required
    expr: '(node_reboot_required > 0) * on(instance) group_left (nodename) node_uname_info{nodename=~".+"}'
    for: 4h
    labels:
      severity: info
    annotations:
      summary: "Host requires reboot"
      description: "Host \"{{ $labels.instance }}\" must be rebooted."
EOF

cat << 'EOF' > /etc/prometheus/rules/prometheus.yaml
groups:
- name: prometheus
  rules:

  - alert: prometheus_configuration_reload_failure
    expr: 'prometheus_config_last_reload_successful != 1'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus configuration reload failure"
      description: "Prometheus failed to reload the configuration."

  - alert: prometheus_too_many_restarts
    expr: 'changes(process_start_time_seconds{job="prometheus"}[15m]) > 2'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus too many restarts"
      description: "Prometheus has restarted more than twice in the last 15 minutes."

  - alert: prometheus_timeseries_cardinality_high
    expr: 'label_replace(count by(__name__) ({__name__=~".+"}), "name", "$1", "__name__", "(.+)") > 10000'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "High Prometheus timeseries cardinality"
      description: "The timeseries cardinality for the metric \"{{ $labels.name }}\" is exceeding 10,000. This could lead to high memory usage and performance degradation."

  - alert: prometheus_notifications_queue_length
    expr: 'min_over_time(prometheus_notifications_queue_length[10m]) > 0'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus notifications backlog"
      description: "Prometheus notification queue has not been empty for over 10 minutes. This may indicate a backlog of alerts waiting to be processed."

  - alert: prometheus_notifications_alertmanagers_discovered
    expr: 'prometheus_notifications_alertmanagers_discovered < 1'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus not connected to Alertmanager"
      description: "Prometheus is unable to connect to the Alertmanager. This may prevent alert notifications from being sent."

  - alert: prometheus_template_text_expansion_failures
    expr: 'increase(prometheus_template_text_expansion_failures_total[3m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus template text expansion failures"
      description: "Prometheus encountered template text expansion failures. This could affect alert descriptions or rule evaluations."

  - alert: prometheus_rule_evaluation_failures
    expr: 'increase(prometheus_rule_evaluation_failures_total[3m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus rule evaluation failures"
      description: "Prometheus has encountered rule evaluation failures, which may cause some alerts to be missed or ignored."

  - alert: prometheus_rule_evaluation_slow
    expr: 'prometheus_rule_group_last_duration_seconds > prometheus_rule_group_interval_seconds'
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus rule evaluation is slow"
      description: "Prometheus rule evaluations are taking longer than their scheduled interval, potentially indicating performance issues or inefficient queries."

  - alert: prometheus_target_missing
    expr: 'up == 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus target missing"
      description: "The Prometheus target \"{{ $labels.instance }}\" is missing or unreachable. This could be caused by a failed exporter or a network issue."

  - alert: prometheus_target_scrape_slow
    expr: 'prometheus_target_interval_length_seconds{quantile="0.9"} / on (interval, instance, job) prometheus_target_interval_length_seconds{quantile="0.5"} > 1.05'
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus target scraping slow"
      description: "Prometheus is scraping exporters slowly since it exceeded the requested interval time. Your Prometheus server is under-provisioned."

  - alert: prometheus_target_scrape_large
    expr: 'increase(prometheus_target_scrapes_exceeded_sample_limit_total[10m]) > 10'
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus large scrape"
      description: "Prometheus has many scrapes that exceed the sample limit."

  - alert: prometheus_target_scrape_duplicate
    expr: 'increase(prometheus_target_scrapes_sample_duplicate_timestamp_total[5m]) > 0'
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "Prometheus target scrape duplicate"
      description: "Prometheus has many samples rejected due to duplicate timestamps but different values."

  - alert: prometheus_tsdb_checkpoint_creation_failed
    expr: 'increase(prometheus_tsdb_checkpoint_creations_failed_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB checkpoint creation failures"
      description: "Prometheus encountered {{ $value }} checkpoint creation failures."

  - alert: prometheus_tsdb_checkpoint_deletion_failed
    expr: 'increase(prometheus_tsdb_checkpoint_deletions_failed_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB checkpoint deletion failures"
      description: "Prometheus encountered {{ $value }} checkpoint deletion failures."

  - alert: prometheus_tsdb_compactions_failed
    expr: 'increase(prometheus_tsdb_compactions_failed_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB compactions failed"
      description: "Prometheus encountered {{ $value }} TSDB compactions failures."

  - alert: prometheus_tsdb_head_truncations_failed
    expr: 'increase(prometheus_tsdb_head_truncations_failed_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB head truncations failed"
      description: "Prometheus encountered {{ $value }} TSDB head truncation failures."

  - alert: prometheus_tsdb_reload_failures
    expr: 'increase(prometheus_tsdb_reloads_failures_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB reload failures"
      description: "Prometheus encountered {{ $value }} TSDB reload failures."

  - alert: prometheus_tsdb_wal_corruptions
    expr: 'increase(prometheus_tsdb_wal_corruptions_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB WAL corruptions"
      description: "Prometheus encountered {{ $value }} TSDB WAL corruptions."

  - alert: prometheus_tsdb_wal_truncations_failed
    expr: 'increase(prometheus_tsdb_wal_truncations_failed_total[1m]) > 0'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus TSDB WAL truncations failed"
      description: "Prometheus encountered {{ $value }} TSDB WAL truncation failures."
EOF

cat << 'EOF' > /etc/prometheus/rules/watchdog.yaml
groups:
- name: watchdog
  rules:

  - alert: watchdog
    expr: 'vector(1)'
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Watchdog"
      description: "This is an alert that should always be active to monitor the overall health of the system."
EOF

# create target files
cat << 'EOF' > /etc/prometheus/targets/servers/server.yaml
- targets:
  - "127.0.0.1:9100"
  labels:
    instance: "server"
EOF

cat << 'EOF' > /etc/prometheus/targets/services/prometheus.yaml
- targets:
  - "127.0.0.1:9090"
  labels:
    instance: "prometheus"
EOF

cat << 'EOF' > /etc/prometheus/targets/services/alertmanager.yaml
- targets:
  - "127.0.0.1:9093"
  labels:
    instance: "alertmanager"
EOF

cat << 'EOF' > /etc/prometheus/targets/services/blackbox_exporter.yaml
- targets:
  - "127.0.0.1:9115"
  labels:
    instance: "blackbox_exporter"
EOF

cat << 'EOF' > /etc/prometheus/targets/services/cadvisor.yaml
- targets:
  - "127.0.0.1:9324"
  labels:
    instance: "cadvisor"
EOF

cat << 'EOF' > /etc/prometheus/targets/services/docker.yaml
- targets:
  - "127.0.0.1:9323"
  labels:
    instance: "docker"
EOF

cat << 'EOF' > /etc/prometheus/targets/services/haproxy.yaml
- targets:
  - "127.0.0.1:8405"
  labels:
    instance: "haproxy"
EOF

cat << 'EOF' > /etc/prometheus/targets/sites/google.yaml
- targets:
  - "https://google.com"
EOF

# copy binaries
install -m 0755 -o ${APP_SA} -g ${APP_SA} ${TEMP_DIR}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/prometheus /usr/local/bin/prometheus
install -m 0755 -o ${APP_SA} -g ${APP_SA} ${TEMP_DIR}/prometheus-${APP_VERSION#v}.linux-${SYSTEM_ARCH}/promtool /usr/local/bin/promtool

# update ownership
chown -R ${APP_SA}:${APP_SA} /etc/prometheus
chown -R ${APP_SA}:${APP_SA} /var/lib/prometheus

# create service
cat << EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Restart=always
User=${APP_SA}
Group=${APP_SA}
ExecStart=/usr/local/bin/prometheus \
--config.file="/etc/prometheus/prometheus.yaml" \
--web.listen-address="0.0.0.0:9090" \
--web.enable-lifecycle \
--web.enable-admin-api \
--storage.tsdb.path="/var/lib/prometheus/" \
--storage.tsdb.retention.time="30d" \
--log.level="info" \
--log.format="logfmt"

[Install]
WantedBy=multi-user.target
EOF

# start and enable service
systemctl --quiet daemon-reload
systemctl --quiet start prometheus.service
systemctl --quiet enable prometheus.service

# status message
echo -e "\033[0;92mINFO:\033[0m installation succeeded"
