{
  lib,
  buildGoModule,
  copyDesktopItems,
  darwin,
  desktopToDarwinBundle,
  fetchFromGitHub,
  fetchYarnDeps,
  gtk3,
  installShellFiles,
  jq,
  libayatana-appindicator,
  libsoup_2_4,
  makeDesktopItem,
  mkYarnPackage,
  openssl,
  pkg-config,
  rust,
  rustPlatform,
  stdenv,
  testers,
  webkitgtk_4_0,
}:

let
  pname = "devpod";
  version = "0.5.20";

  src = fetchFromGitHub {
    owner = "loft-sh";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-8LbqrOKC1als3Xm6ZuU2AySwT0UWjLN2xh+/CvioYew=";
  };

  meta = with lib; {
    description = "Codespaces but open-source, client-only and unopinionated: Works with any IDE and lets you use any cloud, kubernetes or just localhost docker";
    mainProgram = "devpod";
    homepage = "https://devpod.sh";
    license = licenses.mpl20;
    maintainers = with maintainers; [ maxbrunet ];
  };
in
rec {
  devpod = buildGoModule {
    inherit
      version
      src
      pname
      meta
      ;

    vendorHash = null;

    env.CGO_ENABLED = 0;

    ldflags = [
      "-X github.com/loft-sh/devpod/pkg/version.version=v${version}"
    ];

    excludedPackages = [ "./e2e" ];

    nativeBuildInputs = [ installShellFiles ];

    postInstall = ''
      $out/bin/devpod completion bash >devpod.bash
      $out/bin/devpod completion fish >devpod.fish
      $out/bin/devpod completion zsh >devpod.zsh
      installShellCompletion devpod.{bash,fish,zsh}
    '';

    passthru.tests.version = testers.testVersion {
      package = devpod;
      command = "devpod version";
      version = "v${version}";
    };
  };

  devpod-desktop =
    let
      frontend-build = mkYarnPackage {
        inherit version;
        pname = "devpod-frontend";

        src = "${src}/desktop";

        offlineCache = fetchYarnDeps {
          yarnLock = "${src}/desktop/yarn.lock";
          hash = "sha256-vUV4yX+UvEKrP0vHxjGwtW2WyONGqHVmFor+WqWbkCc=";
        };

        packageJSON = ./package.json;

        buildPhase = ''
          export HOME=$(mktemp -d)
          yarn --offline run build

          cp -r deps/devpod/dist $out
        '';

        doDist = false;
        dontInstall = true;
      };

      rustTargetPlatformSpec = stdenv.hostPlatform.rust.rustcTarget;
    in
    rustPlatform.buildRustPackage {
      inherit version src;
      pname = "devpod-desktop";

      sourceRoot = "${src.name}/desktop/src-tauri";

      useFetchCargoVendor = true;
      cargoHash = "sha256-HD9b7OWilltL5Ymj28zoZwv5TJV3HT3LyCdagMqLH6E=";

      # Workaround:
      #   The `tauri` dependency features on the `Cargo.toml` file does not match the allowlist defined under `tauri.conf.json`.
      #   Please run `tauri dev` or `tauri build` or add the `updater` feature.
      # Upstream is not interested in fixing that: https://github.com/loft-sh/devpod/pull/648
      patches = [ ./add-tauri-updater-feature.patch ];

      postPatch =
        ''
          ln -s ${devpod}/bin/devpod bin/devpod-cli-${rustTargetPlatformSpec}
          cp -r ${frontend-build} frontend-build

          substituteInPlace tauri.conf.json --replace '"distDir": "../dist",' '"distDir": "frontend-build",'
        ''
        + lib.optionalString stdenv.hostPlatform.isLinux ''
          substituteInPlace $cargoDepsCopy/libappindicator-sys-*/src/lib.rs \
            --replace "libayatana-appindicator3.so.1" "${libayatana-appindicator}/lib/libayatana-appindicator3.so.1"

          # Since `cargo build` is used instead of `tauri build`, configs are merged manually.
          jq --slurp '.[0] * .[1]' tauri.conf.json tauri-linux.conf.json >tauri.conf.json.merged
          mv tauri.conf.json.merged tauri.conf.json
        '';

      nativeBuildInputs =
        [
          copyDesktopItems
          pkg-config
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          jq
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          desktopToDarwinBundle
        ];

      buildInputs =
        [
          libsoup_2_4
          openssl
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          gtk3
          libayatana-appindicator
          webkitgtk_4_0
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          darwin.apple_sdk.frameworks.Carbon
          darwin.apple_sdk.frameworks.Cocoa
          darwin.apple_sdk.frameworks.WebKit
        ];

      desktopItems = [
        (makeDesktopItem {
          name = "DevPod";
          categories = [ "Development" ];
          comment = "Spin up dev environments in any infra";
          desktopName = "DevPod";
          exec = "DevPod %U";
          icon = "DevPod";
          terminal = false;
          type = "Application";
          mimeTypes = [ "x-scheme-handler/devpod" ];
        })
      ];

      postInstall = ''
        ln -sf ${devpod}/bin/devpod $out/bin/devpod-cli
        mv $out/bin/devpod-desktop $out/bin/DevPod

        mkdir -p $out/share/icons/hicolor/{256x256@2,128x128,32x32}/apps
        cp icons/128x128@2x.png $out/share/icons/hicolor/256x256@2/apps/DevPod.png
        cp icons/128x128.png $out/share/icons/hicolor/128x128/apps/DevPod.png
        cp icons/32x32.png $out/share/icons/hicolor/32x32/apps/DevPod.png
      '';

      meta = meta // {
        mainProgram = "DevPod";
        # darwin does not build
        # https://github.com/h4llow3En/mac-notification-sys/issues/28
        platforms = lib.platforms.linux;
      };
    };
}
