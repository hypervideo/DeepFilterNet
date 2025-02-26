{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , rust-overlay
    , crane
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; overlays = [ (import rust-overlay) ]; };

      rust-toolchain = (pkgs.rust-bin.stable.latest.default).override {
        extensions = [ "rust-analyzer" "rust-src" ];
        targets = [ "wasm32-unknown-unknown" ];
      };

      craneLib = (crane.mkLib nixpkgs.legacyPackages.${system}).overrideToolchain rust-toolchain;

      python = pkgs.python312;

      buildInputs = {
        nativeBuildInputs = with pkgs; [
          rust-toolchain
          pkg-config
          lld
          wasm-pack
          binaryen # wasm-opt
          python
          wasm-bindgen-cli
        ];

        buildInputs = with pkgs; [
          openssl
          clang
          alsa-lib
          hdf5
        ] ++ (if pkgs.stdenv.isDarwin then [ libiconv ] else [ ]);

        wasm-bindgen-cli = pkgs.wasm-bindgen-cli;
      };

      libDF-deps = craneLib.buildDepsOnly (buildInputs // {
        pname = "libDF-deps";
        cargoToml = ./libDF/Cargo.toml;
        src = ./.;
        doCheck = false;
      });

      libDF = craneLib.buildPackage (buildInputs // {
        cargoToml = ./libDF/Cargo.toml;
        src = ./.;
        cargoArtifacts = libDF-deps;
        doCheck = false;

        doNotPostBuildInstallCargoBinaries = true;

        buildPhaseCargoCommand = ''
          export XDG_CACHE_HOME=$(mktemp -d)
          export HOME=$XDG_CACHE_HOME
          sh ./scripts/build_wasm_package.sh
        '';

        installPhaseCommand = ''
          mkdir -p $out/
          cp -r libDF/pkg/* $out/
        '';
      });


      shell = pkgs.mkShell {
        inputsFrom = [ libDF ];

        packages = with pkgs; [ miniserve ];

        RUST_BACKTRACE = "1";
        RUST_LOG = "info";
        LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
      };

    in
    {
      devShells.default = shell;
      packages = { inherit libDF; };
    }
    );
}
