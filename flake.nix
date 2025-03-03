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

      coreAudio =
        if pkgs.stdenv.isDarwin then
        # pkgs.symlinkJoin
          pkgs.buildEnv
            {
              name = "sdk";
              paths = with pkgs.darwin.apple_sdk.frameworks; [
                CoreFoundation
                CoreServices
                SystemConfiguration
                Security
                AudioToolbox
                AudioUnit
                CoreAudio
                CoreFoundation
                CoreMIDI
                OpenAL
              ];
              postBuild = ''
                # mkdir $out/System
                ln -s $out/Library $out/System
              '';
            }
        else
          "";

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
        ] ++ (if pkgs.stdenv.isDarwin then [ libiconv coreAudio ] else [ alsa-lib ]);

        wasm-bindgen-cli = pkgs.wasm-bindgen-cli;
      };

      cargoExtraArgs = "-p deep_filter --no-default-features --features wasm,default-model --target wasm32-unknown-unknown";

      libDF-deps = craneLib.buildDepsOnly (buildInputs // {
        pname = "libDF-deps";
        cargoToml = ./libDF/Cargo.toml;
        src = ./.;
        doCheck = false;
        inherit cargoExtraArgs;
      });

      libDF = craneLib.buildPackage (buildInputs // {
        cargoToml = ./libDF/Cargo.toml;
        src = ./.;
        doCheck = false;
        cargoArtifacts = libDF-deps;
        inherit cargoExtraArgs;

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
