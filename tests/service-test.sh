#!/bin/bash
set -e

DIR="$(dirname "$0")/../debian"
AGENT="$DIR/wlanpi-bluetooth.bt-agent.service"
NETWORK="$DIR/wlanpi-bluetooth.bt-network.service"
CONTROL="$DIR/control"
RULES="$DIR/rules"
POSTINST="$DIR/postinst"

# set -e ignores a command negated with !, so absence checks exit explicitly.
grep -q '^After=bluetooth.service$' "$AGENT"
grep -q '^After=network.target bluetooth.service$' "$NETWORK"
if grep -q '^After=.*bluetooth.target' "$AGENT" "$NETWORK"; then exit 1; fi
grep -q '^ExecStartPre=/usr/sbin/rfkill unblock bluetooth$' "$AGENT"
grep -q '^ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput$' "$AGENT"
grep -q 'for i in 1 2 3 4 5 6 7 8 9 10' "$AGENT"
grep -q '^KillSignal=SIGKILL$' "$AGENT"
grep -q '^SuccessExitStatus=SIGKILL$' "$AGENT"
grep -q '^WantedBy=bluetooth.target$' "$AGENT"
grep -q '^WantedBy=bluetooth.target$' "$NETWORK"
grep -q 'rfkill' "$CONTROL"
grep -q '^\s*dh_installsystemd --name=bt-agent$' "$RULES"
grep -q '^\s*dh_installsystemd --name=bt-network$' "$RULES"
grep -q '^\s*dh_installsystemd --no-enable --no-start --name=bt-timedpair$' "$RULES"
grep -q 'systemctl reenable bt-agent.service bt-network.service' "$POSTINST"
grep -q 'networkctl reload' "$POSTINST"

# networkd disables DHCPServer= when the only address is link-local.
PAN="$DIR/../etc/systemd/network/pan0.network"
grep -q '^DHCPServer=yes$' "$PAN"
grep -q '^Address=198\.18\.43\.1/24$' "$PAN"
if grep -q '169\.254\.' "$PAN"; then exit 1; fi

echo "Bluetooth service checks passed"
