{
  autoPatchelfHook,
  fetchgit,
  lib,
  libfprint-tod,
  openssl,
  patchelfUnstable, # have to use patchelfUnstable to support --rename-dynamic-symbols
  stdenv,
}:

# Based on ideas from (using a wrapper library to redirect fopen() calls to firmware files):
#   * https://tapesoftware.net/replace-symbol/
#   * https://github.com/NixOS/nixpkgs/pull/260715
let
  pname = "libfprint-2-tod1-broadcom";
  version = "5.12.018";

  src = fetchgit {
    url = "git://git.launchpad.net/${pname}";
    rev = "86acc29291dbaf6216b7fadf50ef1e7222f6eb2a";    # head of jammy-staging branch as of 2024-11-20
    hash = "sha256-nCkAqAi1AD3qMIU3maMuOUY6zG6+wDkqUMaHEKcLTko=";
    name = "${pname}-unpacked-${version}";
  };

  wrapperLibName = "wrapper-lib.so";
  wrapperLibSource = "wrapper-lib.c";

  # wraps `fopen()` for finding firmware files
  wrapperLib = stdenv.mkDerivation {
    pname = "${pname}-wrapper-lib";
    inherit version;

    src = builtins.path {
      name = "${pname}-wrapper-lib-source";
      path = ./.;
      filter = path: type: baseNameOf path == wrapperLibSource;
    };

    postPatch = ''
      substitute ${wrapperLibSource} lib.c \
        --subst-var-by to "${src}/var/lib/fprint/fw"
      cc -fPIC -shared lib.c -o ${wrapperLibName}
    '';

    installPhase = ''
      runHook preInstall
      install -D -t $out/lib ${wrapperLibName}
      runHook postInstall
    '';
  };
in
stdenv.mkDerivation {
  inherit src pname version;

  buildInputs = [
    libfprint-tod
    openssl
    wrapperLib
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    patchelfUnstable
  ];

  installPhase = ''
    runHook preInstall
    install -v -D -m 444 -t "$out/lib/libfprint-2/tod-1/" usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so
    install -v -D -m 444 -t "$out/lib/udev/rules.d/"      lib/udev/rules.d/60-libfprint-2-device-broadcom.rules
    runHook postInstall
  '';

  postFixup = ''
    echo fopen64 fopen_wrapper > fopen_name_map
    patchelf \
      --rename-dynamic-symbols fopen_name_map \
      --add-needed ${wrapperLibName} \
      "$out/lib/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"
  '';

  passthru.driverPath = "/lib/libfprint-2/tod-1";

  meta = with lib; {
    description = "Broadcom driver module for libfprint-2-tod Touch OEM Driver (from Dell)";
    homepage = "https://launchpad.net/libfprint-2-tod1-broadcom";
    license = licenses.unfree;
    maintainers = with maintainers; [ pitkling ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
