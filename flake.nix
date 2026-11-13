{
  description = "Stream Deck Bars for World of Warcraft: development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The helper uses ScreenCaptureKit and the plugin targets the macOS
      # Stream Deck app, so only macOS is supported.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        # mkShellNoCC keeps Nix's compiler wrapper and Apple SDK out of the
        # shell, so `swift`, `xcrun` and `codesign` resolve to the system Xcode.
        default = pkgs.mkShellNoCC {
          packages = [
            # Addon tests (`make addon-test`) and fixtures (`make fixtures`)
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.luacov
            ]))

            # Stream Deck plugin
            pkgs.nodejs_24

            # tools/fill-profile.py
            pkgs.python3
          ];

          shellHook = ''
            unset DEVELOPER_DIR SDKROOT

            if ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
              echo "warning: no Swift toolchain found; install Xcode to build the helper" >&2
            fi
          '';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
