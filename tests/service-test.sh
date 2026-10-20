#!/bin/bash
set -e

DIR="$(dirname "$0")/../debian"
AGENT="$DIR/wlanpi-bluetooth.bt-agent.service"
NETWORK="$DIR/wlanpi-bluetooth.bt-network.service"
CONTROL="$DIR/control"
RULES="$DIR/rules"
POSTINST="$DIR/postinst"
TIMEDPAIR="$DIR/wlanpi-bluetooth.bt-timedpair.service"
UDEV="$DIR/../usr/lib/udev/rules.d/90-wlanpi-bluetooth.rules"

# set -e ignores a command negated with !, so absence checks exit explicitly.
grep -q '^After=bluetooth.service$' "$AGENT"
grep -q '^After=network.target bluetooth.service bt-agent.service$' "$NETWORK"
if grep -q '^After=.*bluetooth.target' "$AGENT" "$NETWORK"; then exit 1; fi
grep -q '^ExecStartPre=/usr/sbin/rfkill unblock bluetooth$' "$AGENT"
grep -q '^ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput$' "$AGENT"
# The adapter is chosen at run time (wlanpi-bt-adapter), never hardcoded.
grep -q '^ExecStartPost=/usr/bin/wlanpi-bt-adapter --setup$' "$AGENT"
if grep -q 'hci[0-9]' "$AGENT" "$NETWORK" "$TIMEDPAIR"; then exit 1; fi
grep -q '^PartOf=bt-agent.service$' "$NETWORK"
# Hotplug only try-restarts bt-agent, so it must start bt-network and recover
# from its own failures.
grep -q '^Wants=bt-network.service$' "$AGENT"
grep -q '^Restart=on-failure$' "$AGENT"
grep -q '^RestartSec=5$' "$AGENT"
grep -q '^StartLimitIntervalSec=0$' "$AGENT"

# Run a unit's ExecStart with the /usr/bin tools stubbed. wlanpi-bt-adapter
# prints $ADAPTER, or exits 1 when it is empty.
STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
printf '#!/bin/sh\necho select >> "%s/calls"\n[ -n "$ADAPTER" ] && echo "$ADAPTER"\n' "$STUB" > "$STUB/wlanpi-bt-adapter"
printf '#!/bin/sh\necho "${0##*/} $*" >> "%s/calls"\n' "$STUB" > "$STUB/bt-adapter"
cp "$STUB/bt-adapter" "$STUB/bt-network"
chmod +x "$STUB"/*
run_unit() {
    local cmd
    cmd=$(awk '/^ExecStart=/ { f = 1; sub(/^ExecStart=/, "") }
        f { c = sub(/\\$/, ""); printf "%s", $0; if (!c) exit }' "$1" |
        sed -e 's/\$\$/$/g' -e "s#/usr/bin/#$STUB/#g")
    rm -f "$STUB/calls"
    (export ADAPTER=$2; eval "$cmd") >/dev/null 2>&1
    echo "rc=$? $(tr '\n' ';' < "$STUB/calls")"
}
[ "$(run_unit "$NETWORK" hci1)" = "rc=0 select;bt-network -a hci1 -s nap pan0;" ]
[ "$(run_unit "$NETWORK" "")" = "rc=1 select;" ]
[ "$(run_unit "$TIMEDPAIR" hci1)" = "rc=0 select;bt-adapter -a hci1 --set PairableTimeout 30;bt-adapter -a hci1 --set DiscoverableTimeout 30;bt-adapter -a hci1 --set Pairable 1;bt-adapter -a hci1 --set Discoverable 1;" ]
[ "$(run_unit "$TIMEDPAIR" "")" = "rc=1 select;" ]
[ "$(grep -c '^ExecStart=' "$TIMEDPAIR")" = 1 ]

grep -q '^SUBSYSTEM=="bluetooth", ENV{DEVTYPE}=="host", ACTION=="add|remove", RUN+="/usr/bin/systemctl --no-block try-restart bt-agent.service"$' "$UDEV"
grep -q '^usr/bin/wlanpi-bt-adapter ' "$DIR/wlanpi-bluetooth.install"
grep -q '^usr/lib/udev/rules.d/90-wlanpi-bluetooth.rules ' "$DIR/wlanpi-bluetooth.install"
grep -q '^KillSignal=SIGKILL$' "$AGENT"
grep -q '^SuccessExitStatus=SIGKILL$' "$AGENT"
grep -q '^WantedBy=bluetooth.target$' "$AGENT"
grep -q '^WantedBy=bluetooth.target$' "$NETWORK"
grep -q 'rfkill' "$CONTROL"
grep -q '^\s*dh_installsystemd --name=bt-agent$' "$RULES"
grep -q '^\s*dh_installsystemd --name=bt-network$' "$RULES"
grep -q '^\s*dh_installsystemd --no-enable --no-start --name=bt-timedpair$' "$RULES"
grep -q 'systemctl reenable bt-agent.service bt-network.service' "$POSTINST"
grep -q '^\s*ischroot || networkctl reload 2>/dev/null || true$' "$POSTINST"

# networkd disables DHCPServer= when the only address is link-local.
PAN="$DIR/../etc/systemd/network/pan0.network"
grep -q '^DHCPServer=yes$' "$PAN"
grep -q '^Address=198\.18\.43\.1/24$' "$PAN"
grep -q '^EmitRouter=no$' "$PAN"
if grep -q '169\.254\.' "$PAN"; then exit 1; fi

echo "Bluetooth service checks passed"
