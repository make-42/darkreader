{
  description = "Flake that wraps LibreWolf with a user-configurable extension build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    configurable-flakes.url = "github:sents/configurable-flakes";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    configurable-flakes,
  }: let
    lib = nixpkgs.lib;
  in
    configurable-flakes.lib.configurableFlake inputs {
      options = {
        darkBG = lib.mkOption {
          type = lib.types.str;
          default = "#0d1214";
          description = "Dark background color";
        };
        lightBG = lib.mkOption {
          type = lib.types.str;
          default = "#0d1214";
          description = "Light background color";
        };
        darkText = lib.mkOption {
          type = lib.types.str;
          default = "#cae0eb";
          description = "Dark text color";
        };
        lightText = lib.mkOption {
          type = lib.types.str;
          default = "#cae0eb";
          description = "Light text color";
        };
      };
    }
    ({config, ...}:
      flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = import nixpkgs {inherit system;};

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
          packages.darkLibrewolf = darkFirefox;
          packages.darkreaderAddon = darkreaderAddon;
          defaultPackage = darkFirefox;
        }
      ));
}
