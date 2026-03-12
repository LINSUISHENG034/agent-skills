# Host Linux Checks

Use these commands when the user is asking about the current deployment host. Choose the smallest proof that can answer the question.

## Host identity

```bash
hostnamectl
uname -a
cat /etc/os-release
uptime
date -Is
whoami
pwd
```

## Process and service state

```bash
ps -ef | rg openclaw
pgrep -af 'openclaw|openclaw-gateway'
systemctl --user status openclaw-gateway.service --no-pager
systemctl --user show -p MainPID,ActiveState,SubState openclaw-gateway.service
journalctl --user -u openclaw-gateway.service -n 80 --no-pager
```

## Ports and listeners

```bash
ss -ltnp
ss -ltnup
lsof -nP -iTCP -sTCP:LISTEN
```

## Network basics

```bash
ip addr
ip route
resolvectl status
ping -c 1 8.8.8.8
curl -I https://example.com
```

## Disk and memory

```bash
df -h
free -h
lsblk
mount
```

## Logs

```bash
journalctl -n 80 --no-pager
journalctl -b -n 120 --no-pager
```

## Guidance

- For one-off questions, do not dump all host commands.
- Prefer current state over history unless the user asks for historical diagnosis.
- If a command is missing, say so and use the nearest equivalent only when it answers the same question.
