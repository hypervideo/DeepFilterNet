#!/usr/bin/env sh
set -euo pipefail

# look at DeepFilterNet/.github/workflows/build_wasm.yml for enviroment setup
# see '../.cargo/config.toml' for RUSTFLAGS
cd ./libDF/
wasm-pack build --target web --features "wasm"
