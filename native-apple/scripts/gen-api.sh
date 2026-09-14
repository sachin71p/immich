#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
spec="$script_dir/../../open-api/immich-openapi-specs.json"
target="$script_dir/../PhotosCore/Sources/ImmichAPI/openapi.yaml"

if [ ! -f "$spec" ]; then
  echo "OpenAPI specification not found: $spec" >&2
  exit 1
fi

cp "$spec" "$target"
