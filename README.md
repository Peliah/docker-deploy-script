# Docker Deploy Script (ash)

Small POSIX-compatible ash script to automate setup, deployment and configuration of a Dockerized application on a remote Linux server via SSH.

## Features
- Install Docker and docker-compose (where available)
- Copy application files and an optional .env to the remote host
- Pull/build and run containers (compose or docker run)
- Configure systemd unit for automatic start and restart
- Optional firewall and basic user/ssh setup
- Health-checks, logs collection and simple rollback
- Idempotent operations, dry-run and verbose modes

## Prerequisites
- Local machine: ssh client, ash-compatible shell (script is POSIX).
- Remote server: SSH access as a sudo-capable user, minimal POSIX shell.
- Supported distros: Debian/Ubuntu, RHEL/CentOS, Alpine (best-effort).
- Network access for pulling images and packages.
- Optional: domain and DNS if using TLS/Let's Encrypt.

## Installation
Place the script in your repo, make it executable:
chmod +x deploy.sh

(Optional) create a remote config file `deploy.env` with required variables (see Configuration).

## Basic usage
./deploy.sh --host user@host.example.com --app-dir /opt/myapp --compose-file docker-compose.yml

Common flags:
- --host user@host          Remote SSH target (required)
- --ssh-key PATH            Private key to use for SSH
- --app-dir PATH            Remote application directory (default: /opt/app)
- --compose-file PATH       Compose file to deploy (optional)
- --env-file PATH           Local .env to upload (optional)
- --install-docker          Force install Docker on remote
- --systemd-service NAME    Create/enable a systemd service wrapper
- --dry-run                 Show actions without executing
- --rollback                Roll back to previous deployment snapshot
- --verbose                 Show detailed output
- --help                    Show help and usage

## Configuration (deploy.env example)
APP_NAME=myapp
APP_PORT=3000
DOCKER_IMAGE=myorg/myapp:latest
REMOTE_USER=deploy
REMOTE_DIR=/opt/myapp
DOMAIN=example.com

Save sensitive values in a local `.env` and pass with --env-file.

## Example
1. Upload and deploy a compose stack:
./deploy.sh --host deploy@203.0.113.5 --ssh-key ~/.ssh/id_rsa \
    --app-dir /opt/myapp --compose-file docker-compose.yml --env-file .env

2. Dry run:
./deploy.sh --host deploy@203.0.113.5 --dry-run --verbose

3. Install Docker then deploy:
./deploy.sh --host root@203.0.113.5 --install-docker --compose-file docker-compose.yml

## How it works (summary)
- Connects over SSH and verifies remote prerequisites.
- Installs Docker/docker-compose if requested and supported.
- Creates remote directory, uploads files and environment.
- Uses docker-compose or docker CLI to start containers.
- Persists a systemd service unit (optional) for auto-restart.
- Keeps a timestamped snapshot to allow simple rollback.

## Safety & idempotency
- Script is designed to be repeatable; it checks for existing installations and containers.
- Dry-run shows planned commands without executing.
- Always test on a staging host before production.

## Troubleshooting
- SSH problems: verify reachable host, correct user/key and permissions.
- Package install failures: check distro detection and available package managers.
- Container fails to start: inspect logs on remote (journalctl or docker logs).
- If deploy leaves partial state, use --rollback or manually remove remote dir then redeploy.

## Extending
- Add TLS provisioning (Certbot) and automated renewals.
- Integrate with CI/CD by passing env vars and secrets securely.
- Replace systemd unit with crontab or container orchestrator hooks.

## License
MIT — adapt as needed.

For exact flags, behavior and examples, open the script header and --help output; this README is a concise overview.