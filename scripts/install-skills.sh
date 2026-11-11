#!/usr/bin/env bash
# Link every skill in .agents/skills/ into ~/.agents/skills. When ~/.agents/link.sh
# exists, run it to fan the links out to every installed harness. Idempotent;
# replaces only symlinks.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${HOME}/.agents/skills"
mkdir -p -- "$target_dir"
for skill in "$root"/.agents/skills/*/; do
	skill="${skill%/}"
	name="$(basename -- "$skill")"
	link="${target_dir}/${name}"
	if [[ -L "$link" ]]; then
		current="$(readlink -f -- "$link" || true)"
		if [[ "$current" != "$skill" ]]; then
			printf 'Relinking %s: %s -> %s\n' "$name" "$current" "$skill"
			ln -sfn -- "$skill" "$link"
		fi
	elif [[ -e "$link" ]]; then
		printf 'Refusing to replace a real file or directory: %s\n' "$link" >&2
		exit 1
	else
		ln -s -- "$skill" "$link"
		printf 'Linked %s -> %s\n' "$name" "$skill"
	fi
done

if [[ -x "${HOME}/.agents/link.sh" ]]; then
	"${HOME}/.agents/link.sh"
fi
