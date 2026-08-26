#!/bin/sh
# Generates .env from .env.example. Two kinds of marker are filled in:
#   KEY=<command>    replaced by that command's output
#   KEY=<?question>  asked on the terminal
# Everything else passes through unchanged.
set -eu

cd "$(dirname "$0")"

if [ -e .env ]; then
	printf '.env already exists. Remove it first if you want to start over.\n' >&2
	exit 1
fi

install -m 600 /dev/null .env

# Keep the terminal on fd 3: the loop's stdin is the template, so <?question>
# markers have to read their answers from somewhere else.
exec 3<&0

while IFS= read -r line; do
	case "$line" in
	[A-Z]*'=<?'*'>')
		q=${line#*=<?}
		q=${q%>}
		printf '%s: ' "$q" >&2
		read -r val <&3
		printf '%s=%s\n' "${line%%=*}" "$val"
		;;
	[A-Z]*'=<'*'>')
		cmd=${line#*=<}
		cmd=${cmd%>}
		printf '%s=%s\n' "${line%%=*}" "$(eval "$cmd")"
		;;
	*)
		printf '%s\n' "$line"
		;;
	esac
done < .env.example > .env

printf 'Wrote .env\n' >&2
