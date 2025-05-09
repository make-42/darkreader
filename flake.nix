{
  description = "Flake that wraps LibreWolf with a user-configurable extension build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Get config or fallback to defaults
        config = {
          darkBG = "#0d1214";
          lightBG = "#0d1214";
          darkText = "#cae0eb";
          lightText = "#cae0eb";
        };

        inherit
          (config)
          darkBG
          lightBG
          darkText
          lightText
          ;

        # Local replacement for fetchFirefoxAddon
        fetchLocalFirefoxAddon = {
          name,
          extid ? "nixos@${name}",
          sourceXpi,
        }:
          pkgs.stdenv.mkDerivation {
            inherit name;

            passthru = {
              extid = extid;
            };

            builder = pkgs.writeScript "xpibuilder" ''
              echo "Repacking Firefox addon ${name} into $out"
              UUID="${extid}"
              mkdir -p "$out/$UUID"
              unzip -q ${sourceXpi} -d "$out/$UUID"
              NEW_MANIFEST=$(jq '. + {
                "applications": { "gecko": { "id": "${extid}" } },
                "browser_specific_settings": { "gecko": { "id": "${extid}" } }
              }' "$out/$UUID/manifest.json")
              echo "$NEW_MANIFEST" > "$out/$UUID/manifest.json"
              cd "$out/$UUID"
              zip -r -q -FS "$out/$UUID.xpi" *
              strip-nondeterminism "$out/$UUID.xpi"
              rm -r "$out/$UUID"
            '';

            nativeBuildInputs = [
              pkgs.jq
              pkgs.strip-nondeterminism
              pkgs.unzip
              pkgs.zip
            ];
          };

        # Build the local extension first
        darkreaderXpi = pkgs.buildNpmPackage {
          name = "darkreader-build";
          src = ./.;

          buildInputs = [pkgs.nodejs];

          npmDeps = pkgs.importNpmLock {
            npmRoot = ./.;
          };

          npmConfigHook = pkgs.importNpmLock.npmConfigHook;

          OVERRIDE_DARK_SCHEME_BACKGROUND_COLOR = darkBG;
          OVERRIDE_LIGHT_SCHEME_BACKGROUND_COLOR = lightBG;
          OVERRIDE_DARK_SCHEME_TEXT_COLOR = darkText;
          OVERRIDE_LIGHT_SCHEME_TEXT_COLOR = lightText;

          buildPhase = ''
            echo "Installing deps."
            #npm install
            echo "Subs."
            substituteInPlace src/inject/dynamic-theme/index.ts \
            --replace-fail "let applyNixOverwrite = false;" 'let applyNixOverwrite = true;' \
            --replace-fail "__OVERRIDE_DARK_SCHEME_BACKGROUND_COLOR__" "$OVERRIDE_DARK_SCHEME_BACKGROUND_COLOR" \
            --replace-fail "__OVERRIDE_DARK_SCHEME_TEXT_COLOR__" "$OVERRIDE_DARK_SCHEME_TEXT_COLOR" \
            --replace-fail "__OVERRIDE_LIGHT_SCHEME_BACKGROUND_COLOR__" "$OVERRIDE_LIGHT_SCHEME_BACKGROUND_COLOR" \
            --replace-fail "__OVERRIDE_LIGHT_SCHEME_TEXT_COLOR__" "$OVERRIDE_LIGHT_SCHEME_TEXT_COLOR"
            echo "Build."
            npm run build:firefox
          '';

          installPhase = ''
            mkdir -p $out
            cp build/release/darkreader-firefox.xpi $out/
          '';
        };

        # Use fetch-style wrapping
        darkreaderAddon = fetchLocalFirefoxAddon {
          name = "darkreader";
          sourceXpi = "${darkreaderXpi}/darkreader-firefox.xpi";
        };

        darkFirefox =
          pkgs.wrapFirefox pkgs.librewolf-unwrapped
          {
            nixExtensions = [
              darkreaderAddon
            ];
          };
      in {
        packages.darkLibrefox = darkFirefox;
        packages.darkreaderAddon = darkreaderAddon;
        defaultPackage = darkFirefox;
      }
    );
}
