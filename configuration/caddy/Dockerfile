# Caddy with the Cloudflare DNS module, needed for the DNS-01 challenge:
# the hostnames resolve to a private address, so HTTP-01 cannot work.
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
