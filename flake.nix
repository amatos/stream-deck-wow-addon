{
  description = "Stream Deck Bars for World of Warcraft: development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The helper uses ScreenCaptureKit and the plugin targets the macOS
      # Stream Deck app, so only macOS can build and run everything. The Linux
      # shells cover the addon and the plugin, which don't need macOS.
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          packages = [
            # Addon tests (`make addon-test`), lint (`make addon-lint`) and fixtures (`make fixtures`)
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.luacheck
              ps.luacov
            ]))

            # Stream Deck plugin
            pkgs.nodejs_24

            # tools/fill-profile.py
            pkgs.python3
          ];
        in
        {
          default =
            if pkgs.stdenv.hostPlatform.isDarwin then
              # mkShellNoCC keeps Nix's compiler wrapper and Apple SDK out of the
              # shell, so `swift`, `xcrun` and `codesign` resolve to the system Xcode.
              pkgs.mkShellNoCC {
                inherit packages;

                shellHook = ''
                  unset DEVELOPER_DIR SDKROOT

                  if ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
                    echo "warning: no Swift toolchain found; install Xcode to build the helper" >&2
                  fi
                '';
              }
            else
              # NixOS and other Linux: the addon and plugin targets work; the helper's need macOS.
              pkgs.mkShellNoCC {
                inherit packages;

                shellHook = ''
                  echo "note: the helper (helper-*, dist) needs macOS; addon, fixtures and plugin targets work here" >&2
                '';
              };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
