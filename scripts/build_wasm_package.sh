#!/bin/env bash

set -Eou pipefail
set -x

cd ./libDF/

# see '../.cargo/config.toml' for RUSTFLAGS

# cargo clean
wasm-pack build --target web --no-typescript --features "wasm"
