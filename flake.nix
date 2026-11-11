{
  description = "Copai: a faint, focus-free Wayland answer overlay";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    systems.url = "github:nix-systems/x86_64-linux";
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      ...
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      homeManagerModules.default = import ./home-manager.nix { inherit self; };
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
      packages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = nixpkgs.lib;
        in
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "copai-shell";
            version = "0.1.0";
            # Include only application files, never local credentials or build output.
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./shell.qml
                ./ask.py
              ];
            };
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/copai-shell $out/libexec
              cp shell.qml ask.py $out/share/copai-shell/
              makeWrapper ${lib.getExe pkgs.python3} $out/libexec/copai-ask \
                --add-flags "$out/share/copai-shell/ask.py" \
                --prefix PATH : ${lib.makeBinPath [ pkgs.wl-clipboard ]}
              makeWrapper ${lib.getExe pkgs.quickshell} $out/bin/copai-shell \
                --add-flags "-p $out/share/copai-shell" \
                --prefix PATH : "$out/libexec"
              runHook postInstall
            '';
            meta = {
              description = "Clipboard answers in a transparent, non-focusable Wayland overlay";
              mainProgram = "copai-shell";
              platforms = lib.platforms.linux;
            };
          };
        }
      );
      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/copai-shell";
        };
      });
      defaultPackage = eachSystem (system: self.packages.${system}.default);
    };
}
