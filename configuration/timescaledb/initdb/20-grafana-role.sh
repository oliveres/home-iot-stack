#!/bin/sh
# Read-only role for Grafana. A shell script, not plain SQL, because the
# credentials arrive as environment variables and psql needs them passed in.
set -e

psql -v ON_ERROR_STOP=1 \
     -v grafana_user="${GRAFANA_DB_USER}" \
     -v grafana_password="${GRAFANA_DB_PASSWORD}" \
     -v owner="${POSTGRES_USER}" \
     -v db="${POSTGRES_DB}" \
     --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-'EOSQL'
	CREATE ROLE :"grafana_user" LOGIN PASSWORD :'grafana_password';

	GRANT CONNECT ON DATABASE :"db" TO :"grafana_user";
	GRANT USAGE ON SCHEMA public TO :"grafana_user";
	GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"grafana_user";

	-- Tables created later by the owner (TimescaleDB propagates hypertable
	-- grants to their chunks on its own).
	ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public
	  GRANT SELECT ON TABLES TO :"grafana_user";
EOSQL
