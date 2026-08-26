# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Docker Compose stack for a home IoT server: ChirpStack (LoRaWAN network server), Mosquitto, Node-RED, TimescaleDB, Grafana. It runs as headless Docker on a separate VM — this repo is edited locally and deployed there. Do not run `docker compose` against this stack locally; compose commands in the README are meant for the VM.

Everything — README, code, configs, comments — is in English.

## Layout

`compose.yaml` contains only `include:` of per-service compose files (project name `home-iot`). One compose file per service, except `compose.chirpstack.yaml`, which intentionally holds all five ChirpStack containers (chirpstack, gateway-bridge, mosquitto, postgres, redis) so it maps 1:1 to upstream `chirpstack/chirpstack-docker`.

All secrets live in `.env`, generated from `.env.example` by `setup-env.sh` (`<command>` markers are executed, `<?question>` markers are prompted), and injected via compose `environment:`. `.env` and `configuration/mqtt/passwd` are gitignored.

## Two brokers — don't confuse them

- `mosquitto` (inside the ChirpStack file): internal only, carries gateway-bridge ↔ chirpstack traffic, no published port, no auth, upstream config untouched.
- `mqtt` (`compose.mqtt.yaml`): the main home broker. Password-protected (`configuration/mqtt/passwd`), publishes 1883. ChirpStack's `[integration.mqtt]` points here, so device uplinks land on the same broker as Node-RED, Loxone, and ESP clients.

## Upstream tracking (the key mechanism)

`configuration/{chirpstack,chirpstack-gateway-bridge,mosquitto,postgresql}` are not hand-written — `bootstrap-upstream.sh` copies them from `chirpstack/chirpstack-docker` and records the upstream commit SHA in `UPSTREAM`. These directories don't exist until the script runs.

**`configuration/chirpstack/chirpstack.toml` is generated from a heredoc inside `bootstrap-upstream.sh`** (env-var references instead of hardcoded secrets). To change ChirpStack server config, edit the heredoc in the script — the generated file is overwritten on every bootstrap run.

Upstream diffing uses the `git upstream-diff` alias described in the README (diffs upstream against itself between two points in time, so local changes don't pollute the diff). After reviewing changes: update `UPSTREAM` with the new SHA and commit.

`bootstrap-upstream.sh` must stay executable (mode 755) — re-`chmod +x` if a GitHub API write resets it.

## Conventions and gotchas

- Image tags for ChirpStack dependencies (postgres, redis, mosquitto) are deliberately aligned with what Debian 13 ships, not with upstream's compose file (exception: the mosquitto `2` tag now resolves to 2.1.x, newer than Debian — kept floating on purpose) — see the version table in the README before bumping them.
- Compose interpolates `$` inside unquoted `.env` values (a letter-led `$run` is treated as a variable reference and silently becomes empty); single-quote a value to keep it literal. All credentials in `.env` are deliberately plaintext — Node-RED's admin password is bcrypt-hashed at container start by `settings.js`.
- Node-RED: only `settings.js` is in git (mounted read-only); `/data` (flows, credentials, node_modules) is a named volume. Grafana: `provisioning/` in git, data in a volume.
- TimescaleDB init scripts live in `configuration/timescaledb/initdb/` and run only on an empty data directory. `TSDB_USER` is the owner (writers use it); Grafana gets a separate read-only role created by `20-grafana-role.sh` — a shell script rather than plain SQL because the credentials arrive as environment variables. Grafana is the one service intended to be reachable from the internet, so keep owner credentials out of it.
- README documents the first-run steps (mosquitto `passwd` generation with 1883:1883/600 ownership, ChirpStack device-profiles import via one-shot `docker compose run`) — keep it in sync when changing any of those flows.
