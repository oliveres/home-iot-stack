# Home IoT stack — ChirpStack, Mosquitto, Node-RED, TimescaleDB, Grafana

Headless Docker on a dedicated VM. One Compose project (`home-iot`), one
compose file per service, `compose.yaml` is nothing but `include`.

ChirpStack is deliberately a single file — five containers, one appliance,
mapping 1:1 onto upstream `chirpstack/chirpstack-docker`.

## Files

| File | Contents |
|---|---|
| `compose.yaml` | `include` only |
| `compose.chirpstack.yaml` | chirpstack, gateway-bridge, mosquitto, postgres, redis |
| `compose.mqtt.yaml` | home MQTT broker |
| `compose.timescaledb.yaml` | TimescaleDB |
| `compose.grafana.yaml` | Grafana |
| `compose.nodered.yaml` | Node-RED |
| `compose.caddy.yaml` | Caddy, HTTPS reverse proxy |
| `setup-env.sh` | writes `.env` from `.env.example` |
| `bootstrap-upstream.sh` | fetches upstream configs, writes `UPSTREAM` |
| `UPSTREAM` | upstream commit the configs came from |

## First run

Everything runs as a regular user; `sudo` appears only in step 0 and for
the ownership of the broker password file.

**0. Docker**

From the official repository, not Debian's `docker.io` — that ships
Engine 26.1.5 and stays there until the release goes out of support.

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
```

Then log out and back in so the group membership takes effect (`id -nG`
has to list `docker`). Without it every `docker` command fails with
permission denied on the socket.

**1. Repository**

```bash
git clone https://github.com/oliveres/home-iot-stack ~/home-iot-stack
cd ~/home-iot-stack
```

**2. DNS and HTTPS**

Grafana, Node-RED and ChirpStack's web UI sit behind Caddy on subdomains
of `DOMAIN`. Their
records point at the VM's private address, so the ACME HTTP-01 challenge
can never reach them — hence DNS-01, which proves control of the domain
by writing a TXT record instead. That is also why Caddy is built from
`configuration/caddy/Dockerfile`: the DNS providers are compiled-in
modules and the stock `caddy:2` image carries none of them.

In Cloudflare's DNS tab, add an A record per service pointing at the VM.
Set each one to **DNS only** (grey cloud) — proxying a private address
through Cloudflare cannot work:

```
grafana.<domain>   A   <private IP of the VM>
nodered.<domain>   A   <private IP of the VM>
mqtt.<domain>      A   <private IP of the VM>
```

`mqtt.<domain>` does double duty: Caddy serves ChirpStack's web UI on it
over HTTPS, and MQTT clients use the same name for the plain broker on
1883, which never touches Caddy.

Then create the API token under My Profile - API Tokens - Create Token,
starting from the **Edit zone DNS** template. It needs `Zone:Zone:Read`
and `Zone:DNS:Edit`, and under Zone Resources pick **Include - Specific
zone - this domain**, so the token cannot touch any other zone on the
account. Put it in `.env` as `CF_API_TOKEN` and the second-level domain
in `DOMAIN`.

**3. Configuration**

```bash
./setup-env.sh            # writes .env, asks for the domain and the token
./bootstrap-upstream.sh   # fetches ChirpStack's upstream configs
```

`setup-env.sh` fills in what `.env.example` marks: `<command>` becomes
that command's output, `<?question>` is asked on the terminal. Unmarked
lines pass through, so `TZ` and the account names keep their values.
`=+/` is stripped from generated passwords so they cannot break
connection strings. The script refuses to run if `.env` already exists.

**4. Home broker accounts**

Mosquitto only reads passwords from a `password_file` as PBKDF2-SHA512
hashes — an environment variable will not do. This builds
`configuration/mqtt/passwd` from every `MQTT_*_USER` and
`MQTT_*_PASSWORD` pair in `.env`.

```bash
docker run --rm --env-file .env -v ./configuration/mqtt:/c eclipse-mosquitto:2 sh -c '
  : > /c/passwd
  for p in $(env | sed -n "s/^\(MQTT_[A-Z0-9_]*\)_USER=.*/\1/p"); do
    printf "%s:%s\n" "$(printenv "${p}_USER")" "$(printenv "${p}_PASSWORD")" >> /c/passwd
  done
  mosquitto_passwd -U /c/passwd
  chown 1883:1883 /c/passwd
  chmod 600 /c/passwd
'
```

The passwords land in the file as plaintext first and `mosquitto_passwd -U`
hashes them in place, so none of them ever appears on a command line.
Owner 1883 is mosquitto inside the container — without it the broker logs
a warning on every load and future versions will refuse the file.

The file is gitignored, hashes of real passwords do not belong in the
repository, and the broker will not start without it. Add an account by
adding the pair of lines to `.env` and running the same command again; a
running broker picks up the change on `docker compose kill -s HUP mqtt`.
Print the passwords any time with `grep MQTT_ .env`.

**5. Start**

```bash
docker compose up -d
```

Then change ChirpStack's `admin/admin` password on `:8080` right away.
Caddy is built on the first `up`, which takes a minute.

**6. Device profiles** (optional)

The catalogue from `chirpstack/chirpstack-device-profiles`. The import
runs the schema migrations itself and only needs postgres reachable — the
server does not have to be up. It is an upsert, so the same commands also
serve to refresh the profiles later (delete the old `/tmp/dp` first).

```bash
git clone --depth 1 https://github.com/chirpstack/chirpstack-device-profiles /tmp/dp
docker compose run --rm -v /tmp/dp:/dp chirpstack -c /etc/chirpstack import-device-profiles -d /dp
```

Profiles can be created by hand in the web UI instead.

## Ports

| Port | Service |
|---|---|
| 8080 | ChirpStack web UI (admin/admin, change immediately) |
| 1700/udp | gateway bridge — where the MikroTik points |
| 1883 | home broker `mqtt` |
| 1880 | Node-RED |
| 3000 | Grafana |
| 5432 | TimescaleDB |
| 80, 443 | Caddy |

ChirpStack's internal postgres, redis and mosquitto are not published.

## ChirpStack dependency versions

Upstream's compose file has `postgres:14-alpine` and `redis:7-alpine`,
which does not match what their own bare-metal instructions give you
(`apt install postgresql redis-server mosquitto`). The tags are therefore
aligned with what Debian 13 ships:

| Service | Debian 13.6 | Here | Documented minimum |
|---|---|---|---|
| PostgreSQL | 17 | `postgres:17-alpine` | v13+ |
| Redis | 8.0.2 | `redis:8-alpine` | 6.2.0+ |
| Mosquitto | 2.0.21 | `eclipse-mosquitto:2` (2.1.x) | MQTT v5 + shared subs |

Verified on trixie with `apt install -V -s postgresql redis mosquitto`
(apt 3.0 no longer prints versions in the summary without `-V`).

Mosquitto's `2` tag now resolves to the 2.1 line, newer than Debian 13 —
left floating on purpose.

## Tracking upstream

`UPSTREAM` holds the commit the configs came from. The diff is upstream
against itself at two points in time, so local edits stay out of it:

```bash
git remote add upstream https://github.com/chirpstack/chirpstack-docker
git config alias.upstream-diff '!git fetch -q upstream && \
  git diff $(cat UPSTREAM)..upstream/master -- configuration/'
```

```bash
git upstream-diff
```

Once the changes have been reviewed:

```bash
git rev-parse upstream/master > UPSTREAM
git commit -am "sync upstream config"
```

`chirpstack.toml` is our own (environment variables instead of secrets),
so only read the upstream version out of the diff and port changes by
hand. The substantive changes tend to be in `region_eu868.toml` whenever
the LoRaWAN regional parameters are revised.

## Notes

- `bootstrap-upstream.sh` has to stay executable. Should it ever revert to
  mode 644 (a write through the GitHub API, say), `chmod +x` and commit.
- ChirpStack needs only the `pg_trgm` extension. `hstore` was required
  back in v3, no longer in v4.
- Node-RED: only `settings.js` is in git, `/data` (flows, credentials,
  node_modules) is a named volume. Node-RED 5 requires Node.js 22.9+ and
  dropped 32-bit ARM (RPi 3B and older). The editor's admin password is
  plaintext in `.env`; `settings.js` bcrypt-hashes it at startup, using
  the image's bundled bcryptjs via `NODE_PATH`.
- TimescaleDB: the volume targets `/var/lib/postgresql`, not `.../data` —
  postgres 18+ keeps its data in a major-version subdirectory. That is why
  ChirpStack's postgres 17 has a different mount.
- Grafana: `provisioning/` in git, `/var/lib/grafana` a volume. Only the
  `datasources` subdirectory is mounted, not all of `provisioning` —
  otherwise the empty `dashboards`, `plugins` and `alerting` directories
  from the image disappear and Grafana reports each one as an error on
  every start. `postgresVersion: 1500` means "15 and newer"; Grafana knows
  no higher value for that field. It reaches TimescaleDB under its own
  read-only role, created by `initdb/20-grafana-role.sh` on the database's
  first start; `TSDB_USER` is the owner and belongs to the writer
  (Node-RED).
- Caddy is built locally (`configuration/caddy/Dockerfile`) because DNS
  challenge providers are compiled into the binary. The Caddyfile reads
  `{$DOMAIN}` at load time and the API token as `{env.CF_API_TOKEN}` at
  runtime, so neither the domain nor the token is in the repository. The
  direct ports (3000, 1880, 8080) stay published as a way back in.
- Two Mosquitto containers: `mosquitto` inside the ChirpStack stack only
  carries traffic between the gateway bridge and the server (no port, no
  auth, upstream config untouched), while `mqtt` is the main home broker
  with passwords on 1883. ChirpStack's `[integration.mqtt]` points at
  `mqtt`, so uplinks land where Node-RED is.
