#!/bin/sh
# INV-02 (S10): OpenAPI diff vs the base upstream tag.
# Fails on any removal, rename, or type change; additions are always allowed.
# Usage: bash scripts/fork-test/openapi-diff.sh [base-ref] [spec-path]
set -eu

base_ref="${1:-e55ac299a4ec7cb372e35dbf2c6c05ee9ce77f6c}"
spec_path="${2:-open-api/immich-openapi-specs.json}"
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

git -C "$root" show "$base_ref:open-api/immich-openapi-specs.json" > "$tmpdir/base.json"

BASE="$tmpdir/base.json" CURRENT="$root/$spec_path" python3 - "$base_ref" <<'EOF'
import json
import os
import sys

base = json.load(open(os.environ['BASE']))
current = json.load(open(os.environ['CURRENT']))
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


base_paths = base.get('paths', {})
current_paths = current.get('paths', {})
for path, item in base_paths.items():
    check(path in current_paths, f'removed path: {path}')
    for method, operation in (item or {}).items():
        if method == 'parameters':
            continue
        check(
            method in (current_paths.get(path) or {}),
            f'removed operation: {method.upper()} {path}',
        )

base_schemas = (base.get('components') or {}).get('schemas', {})
current_schemas = (current.get('components') or {}).get('schemas', {})
for name, schema in base_schemas.items():
    check(name in current_schemas, f'removed schema: {name}')
    current_schema = current_schemas.get(name) or {}
    for prop, definition in (schema.get('properties') or {}).items():
        check(
            prop in (current_schema.get('properties') or {}),
            f'removed property: {name}.{prop}',
        )
        current_definition = (current_schema.get('properties') or {}).get(prop) or {}
        for key in ('type', 'format'):
            if key in definition:
                check(
                    current_definition.get(key) == definition[key],
                    f'type change: {name}.{prop}.{key}: {definition[key]} -> '
                    f'{current_definition.get(key)}',
                )
    for required in schema.get('required') or []:
        check(
            required in (current_schema.get('required') or []),
            f'removed required field: {name}.{required}',
        )

if errors:
    print(f'INV-02 FAIL: {len(errors)} breaking change(s) vs {sys.argv[1]}:')
    for error in errors:
        print(f'  - {error}')
    sys.exit(1)

added_paths = [p for p in current_paths if p not in base_paths]
added_schemas = [s for s in current_schemas if s not in base_schemas]
print(f'INV-02 PASS: no removals/renames/type changes (+{len(added_paths)} paths, +{len(added_schemas)} schemas)')
EOF
