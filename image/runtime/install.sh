#!/bin/sh
set -eu

runtime_dir=${PLOT_AIRGAP_RUNTIME_DIR:-/tmp/plot-airgap}

install -d -m 0755 /etc/nftables /etc/containers/systemd /usr/local/sbin
install -d -m 0755 /var/lib/plot/data /var/lib/plot/workspace /var/lib/plot/models
install -m 0644 "$runtime_dir/90-plot-airgap.nft" /etc/nftables/90-plot-airgap.nft
install -m 0644 "$runtime_dir/plot.container" /etc/containers/systemd/plot.container
install -m 0644 "$runtime_dir/llama.container" /etc/containers/systemd/llama.container
install -m 0644 "$runtime_dir/plot-airgap-firewall.service" /etc/systemd/system/plot-airgap-firewall.service
install -m 0755 "$runtime_dir/import-media.sh" /usr/local/sbin/plot-import-media

systemctl enable plot-airgap-firewall.service
systemctl disable --now dnf-makecache.timer 2>/dev/null || true
systemctl disable --now packagekit.service 2>/dev/null || true
if command -v restorecon >/dev/null 2>&1; then
    restorecon -RFv /etc/containers/systemd /var/lib/plot
fi
rm -rf /tmp/plot-airgap
