{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.pkg-config # pkg-config
    pkgs.zig_0_15 # Zig compiler
    pkgs.zls # Zig LSP
    pkgs.nil # Nix LSP
  ];

  buildInputs = [
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.pipewire
  ];
}
