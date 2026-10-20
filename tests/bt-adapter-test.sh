#!/bin/bash
# Behaviour test for usr/bin/wlanpi-bt-adapter: adapter choice on fake sysfs
# trees modelled on the lab units, and --setup with stubbed busctl,
# bt-adapter and sleep.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/usr/bin/wlanpi-bt-adapter"
TMP=$(mktemp -d) || exit 2
export TMP
trap 'rm -rf "$TMP"' EXIT
fails=0

new_sysfs() {
    SYS="$TMP/sys"
    rm -rf "$SYS"
    mkdir -p "$SYS/bus/usb" "$SYS/bus/serial" "$SYS/class/bluetooth"
}

# usb NAME USBPATH CLASS... : USB device whose interface 1.0 is the adapter.
usb() {
    local name=$1 path=$2 dev i=0 class
    shift 2
    dev="$SYS/devices/usb1/$path"
    for class in "$@"; do
        mkdir -p "$dev/$path:1.$i"
        echo "$class" > "$dev/$path:1.$i/bInterfaceClass"
        ln -s "$SYS/bus/usb" "$dev/$path:1.$i/subsystem"
        i=$((i + 1))
    done
    mkdir -p "$dev/$path:1.0/bluetooth/$name"
    ln -s "$dev/$path:1.0" "$dev/$path:1.0/bluetooth/$name/device"
    ln -s "$dev/$path:1.0/bluetooth/$name" "$SYS/class/bluetooth/$name"
}

# uart NAME : onboard radio on the serial bus.
uart() {
    local dev="$SYS/devices/serial0/serial0-0"
    mkdir -p "$dev/bluetooth/$1"
    ln -s "$SYS/bus/serial" "$dev/subsystem"
    ln -s "$dev" "$dev/bluetooth/$1/device"
    ln -s "$dev/bluetooth/$1" "$SYS/class/bluetooth/$1"
}

# connection NAME : an hciN:M link entry, which is not an adapter.
connection() {
    mkdir -p "$SYS/devices/link/$1"
    ln -s "$SYS/devices/link" "$SYS/devices/link/$1/device"
    ln -s "$SYS/devices/link/$1" "$SYS/class/bluetooth/$1"
}

check() {
    local name=$1 want=$2 got rc
    got=$(WLANPI_BT_SYSFS="$SYS" "$SCRIPT")
    rc=$?
    [ "$want" = none ] && { [ "$rc" = 1 ] && [ -z "$got" ] && got=none; }
    if [ "$got" = "$want" ]; then
        printf 'PASS  %-52s %s\n' "$name" "$got"
    else
        printf 'FAIL  %-52s got=%s rc=%s want=%s\n' "$name" "$got" "$rc" "$want"
        fails=$((fails + 1))
    fi
}

new_sysfs; uart hci0
check "R4: onboard only" hci0

new_sysfs; usb hci0 3-2 e0 e0 e0 ff; uart hci1
check "R5: onboard beats a combo dongle at hci0" hci1

new_sysfs; usb hci0 1-1.2 e0 e0 ff; usb hci1 1-1.3 e0 e0
check "M4: M.2 Bluetooth beats a combo dongle at hci0" hci1

new_sysfs; usb hci1 1-1.3 e0 e0; usb hci0 1-1.4 e0 e0
check "Pro: two M.2 cards, lower USB path wins" hci1
new_sysfs; usb hci0 1-1.3 e0 e0; usb hci1 1-1.4 e0 e0
check "Pro: same with the indexes swapped" hci0

new_sysfs; usb hci0 1-1.3 e0 e0; connection hci0:256
check "connection entry is not an adapter" hci0

new_sysfs
check "no adapter: exit 1, no output" none

# --setup, with stubs that log bt-adapter calls and report which adapters
# BlueZ has registered (REGISTERED, all only after BUSY_CALLS lookups, and
# LATE only after LATE_CALLS lookups).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
n=$(( $(cat "$TMP/busy" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$TMP/busy"
[ "$n" -gt "${BUSY_CALLS:-0}" ] || exit 1
[ "${4##*/}" = "${LATE:-}" ] && [ "$n" -le "${LATE_CALLS:-0}" ] && exit 1
case " $REGISTERED " in *" ${4##*/} "*) exit 0 ;; esac
exit 1
EOF
printf '#!/bin/sh\necho "$*" >> "$TMP/calls"\n' > "$TMP/bin/bt-adapter"
printf '#!/bin/sh\n:\n' > "$TMP/bin/sleep"
printf '#!/bin/sh\necho wlanpi-test\n' > "$TMP/bin/hostname"
chmod +x "$TMP/bin/"*

setup() {
    rm -f "$TMP/calls" "$TMP/busy"
    PATH="$TMP/bin:$PATH" WLANPI_BT_SYSFS="$SYS" \
        "$SCRIPT" --setup > "$TMP/out" 2>/dev/null
    echo $?
}

check_setup() {
    local name=$1 want_rc=$2 want_calls=$3 rc got
    rc=$(setup)
    got=$(sed '0,/--set Powered/s/--set Powered .*/--set Powered x/' "$TMP/calls" 2>/dev/null | tr '\n' ';')
    if [ "$rc" = "$want_rc" ] && [ "$got" = "$want_calls" ]; then
        printf 'PASS  %-52s rc=%s\n' "$name" "$rc"
    else
        printf 'FAIL  %-52s rc=%s calls=%s want rc=%s calls=%s\n' "$name" "$rc" "$got" "$want_rc" "$want_calls"
        fails=$((fails + 1))
    fi
}

new_sysfs; usb hci0 3-2 e0 e0 e0 ff; uart hci1
REGISTERED="hci0 hci1" check_setup "--setup R5: configure hci1, power off hci0" 0 \
    "-a hci1 --set Alias wlanpi-test;-a hci1 --set Powered x;-a hci1 --set Pairable 0;-a hci0 --set Powered 0;"
REGISTERED="hci0 hci1" BUSY_CALLS=5 check_setup "--setup waits until BlueZ registers the adapter" 0 \
    "-a hci1 --set Alias wlanpi-test;-a hci1 --set Powered x;-a hci1 --set Pairable 0;-a hci0 --set Powered 0;"
REGISTERED="hci0 hci1" LATE=hci0 LATE_CALLS=8 check_setup "--setup waits for another adapter to power it off" 0 \
    "-a hci1 --set Alias wlanpi-test;-a hci1 --set Powered x;-a hci1 --set Pairable 0;-a hci0 --set Powered 0;"
REGISTERED="hci1" check_setup "--setup skips an unregistered other adapter" 0 \
    "-a hci1 --set Alias wlanpi-test;-a hci1 --set Powered x;-a hci1 --set Pairable 0;"
REGISTERED="hci0" check_setup "--setup fails if BlueZ never registers it" 1 ""
new_sysfs
REGISTERED="" check_setup "--setup with no adapter does nothing" 0 ""

[ "$fails" -eq 0 ] && echo "wlanpi-bt-adapter: all cases passed" || echo "wlanpi-bt-adapter: $fails case(s) failed"
[ "$fails" -eq 0 ]
