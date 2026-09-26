{ pkgs ? import (fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/34ca302a9572963c02e385c056be37c85ff51b77.tar.gz";
    sha256 = "05hh42z0glkdrl11fqch3n4733rfnmb8c7lji2q6dfqgbwdh2vna";
  }) { }
}:

pkgs.mkShell {
  packages = [
    pkgs.python312
    pkgs.gcc
    pkgs.gnumake
    pkgs.binutils
  ];

  shellHook = ''
    export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}"
  '';
}
