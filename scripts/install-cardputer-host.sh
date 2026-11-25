#!/usr/bin/env bash
# Run manually with sudo after building. Does not start services or alter sshd_config.
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# != 1 ]]; then
  echo 'Usage: sudo bash scripts/install-cardputer-host.sh HOST_LAN_IPV4' >&2
  exit 2
fi
alice_lan="$1"
/usr/bin/python - "$alice_lan" <<'PY'
import ipaddress, sys
address = ipaddress.ip_address(sys.argv[1])
networks = ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')
if address.version != 4 or not any(address in ipaddress.ip_network(n) for n in networks):
    raise SystemExit('Use the host LAN IPv4 address, e.g. 192.168.1.100.')
PY
if [[ $EUID != 0 ]]; then echo 'Run this installer with sudo.' >&2; exit 1; fi
for alice_command in sshd ssh-keygen useradd getent install systemctl; do
  command -v "$alice_command" >/dev/null
done
test -x "$alice_root/target/release/alice-card-server" || {
  echo 'First run bash scripts/build-cardputer-host.sh as your normal user.' >&2; exit 1;
}
if getent passwd alice-card >/dev/null; then
  alice_account="$(getent passwd alice-card)"
  if [[ "$alice_account" != *':Alice Cardputer SSH test:/var/lib/alice-card:/usr/local/libexec/alice-card-login' ]]; then
    echo 'An unrelated alice-card user exists; refusing to change it.' >&2; exit 1
  fi
fi
install -d -m 755 /usr/local/libexec
# Atomic replacement permits updating the binary while existing sessions finish.
install -m 755 "$alice_root/target/release/alice-card-server" /usr/local/libexec/alice-card-server.new
mv -f /usr/local/libexec/alice-card-server.new /usr/local/libexec/alice-card-server
cat > /usr/local/libexec/alice-card-login <<'SH'
#!/usr/bin/sh
# Also restricts this account if it connects through the host's ordinary sshd.
# Ignore -c, SSH_ORIGINAL_COMMAND and all user-supplied arguments/environment.
exec /usr/bin/env -i HOME=/var/lib/alice-card PATH=/usr/bin:/bin \
  /usr/local/libexec/alice-card-server --data-dir /var/lib/alice-card/save
SH
chmod 755 /usr/local/libexec/alice-card-login
if ! getent passwd alice-card >/dev/null; then
  useradd --system --user-group --home-dir /var/lib/alice-card \
    --shell /usr/local/libexec/alice-card-login --comment 'Alice Cardputer SSH test' alice-card
fi
install -d -o root -g root -m 755 /var/lib/alice-card
install -d -o alice-card -g alice-card -m 700 /var/lib/alice-card/save
if [[ ! -f /etc/ssh/alice_card_ed25519_key ]]; then
  ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/alice_card_ed25519_key
fi
cat > /etc/ssh/sshd_config_alice_card <<EOF
# Separate LAN test endpoint. Original /etc/ssh/sshd_config is untouched.
Port 2222
AddressFamily inet
ListenAddress $alice_lan
HostKey /etc/ssh/alice_card_ed25519_key
PidFile /run/sshd-alice-card.pid
AllowUsers alice-card
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication no
PermitEmptyPasswords no
UsePAM yes
PermitTTY no
DisableForwarding yes
PermitTunnel no
PermitUserRC no
PermitUserEnvironment no
PrintMotd no
PrintLastLog no
MaxAuthTries 3
MaxSessions 1
LoginGraceTime 30
ClientAliveInterval 30
ClientAliveCountMax 3
ForceCommand /usr/local/libexec/alice-card-server --data-dir /var/lib/alice-card/save
EOF
chmod 600 /etc/ssh/sshd_config_alice_card
/usr/bin/sshd -t -f /etc/ssh/sshd_config_alice_card
cat > /etc/systemd/system/alice-card-sshd.service <<'UNIT'
[Unit]
Description=Alice Cardputer LAN SSH test endpoint
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/bin/sshd -t -f /etc/ssh/sshd_config_alice_card
ExecStart=/usr/bin/sshd -D -e -f /etc/ssh/sshd_config_alice_card
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
echo 'Installed. Set the dedicated account password, then start the service:'
echo '  sudo passwd alice-card'
echo '  sudo systemctl enable --now alice-card-sshd.service'
echo 'Trusted host fingerprint (copy SHA256:... into alice.local.json):'
ssh-keygen -lf /etc/ssh/alice_card_ed25519_key.pub -E sha256
