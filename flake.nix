{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
  };
  outputs =
    {
      nixpkgs,
      flake-parts,
      systems,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;
      perSystem =
        {
          self',
          pkgs,
          config,
          lib,
          ...
        }:
        {
          packages = rec {
            default = hearthstone-linux;
            hearthstone-data =
              pkgs.runCommandLocal "hearthstone-data"
                rec {
                  NGDP_BIN = "${keg}/bin/ngdp";
                  REGION = "eu";
                  version = VERSION;
                  # See https://github.com/Michal-Atlas/hearthstone-linux/blob/master/craft.sh#L81
                  VERSION = "30.2.2.206433.205267";
                  LOCALE = "enUS";
                  outputHash = "sha256-FOsKQNyCbLGRLtVFUye9qk300WHxlwF6JD4XXnEhm/0=";
                  outputHashMode = "recursive";
                }
                ''
                  $NGDP_BIN init
                  $NGDP_BIN remote add http://''${REGION}.patch.battle.net:1119/hsb
                  $NGDP_BIN --cdn "http://level3.blizzard.com/tpr/hs" fetch http://''${REGION}.patch.battle.net:1119/hsb --tags OSX --tags ''${LOCALE} --tags Production
                  $NGDP_BIN install http://''${REGION}.patch.battle.net:1119/hsb $VERSION --tags OSX --tags ''${LOCALE} --tags Production $out
                '';
            hearthstone-data-transformed =
              let
                prefix = pref: file: pkgs.linkFarm "hearthstone-data-t" { ${pref} = file; };
                resSubdir = subdir: "${hearthstone-data}/Hearthstone.app/Contents/Resources/${subdir}";
              in
              pkgs.symlinkJoin {
                name = "hearthstone-data-transformed";
                paths = [
                  hearthstone-data
                  hearthstone-unity
                  hearthstone-linux-stubs
                ];
                # https://github.com/Michal-Atlas/hearthstone-linux/blob/master/craft.sh#L177C3-L179C89
                postBuild = ''
                  cd $out
                  mkdir -p Bin
                  mv Hearthstone.app/Contents/Resources/Data/* Bin/Hearthstone_Data
                  mv Hearthstone.app/Contents/Resources/'unity default resources' Bin/Hearthstone_Data/Resources
                  mv Hearthstone.app/Contents/Resources/PlayerIcon.icns Bin/Hearthstone_Data/Resources
                  rm -r Hearthstone.app
                  rm -r 'Hearthstone Beta Launcher.app'
                '';
              };
            keg =
              with pkgs.python3Packages;
              buildPythonPackage rec {
                pname = "keg";
                version = "0.0.0";
                src = pkgs.fetchFromGitHub {
                  owner = "0xf4b1";
                  repo = pname;
                  rev = "3c8b63420c2f91381f06ecb744122b16c5fb65a0";
                  hash = "sha256-CtssW/yf9CeM2eQWwa/V8KAOC29ObDghiUFMoglB0BA=";
                };
                build-system = [ setuptools ];
                dependencies = [
                  requests
                  click
                  humanize
                  tabulate
                  tqdm
                  parsimonious
                  pycryptodome
                  bitarray
                  toml
                ];
              };
            hearthstone-unity =
              pkgs.runCommandLocal "hearthstone-unity-extract"
                {
                  version = "2021.3.40f1";
                  src = pkgs.fetchzip rec {
                    url = "https://download.unity3d.com/download_unity/6fcab7dbbbc1/LinuxEditorInstaller/Unity.tar.xz";
                    hash = "sha256-qagzM6scoU3Z/ceNa2ypUl0gVdfKpDzazVWGkRAcEKY=";
                  };
                }
                ''
                  mkdir -p $out/Bin
                  cd $src/Data/PlaybackEngines/LinuxStandaloneSupport/Variations/linux64_player_development_mono
                  cp LinuxPlayer $out/Bin/Hearthstone.x86_64
                  cp UnityPlayer.so $out/
                  cp -r Data/MonoBleedingEdge/ $out/Bin/Hearthstone_Data
                  echo $version > $out/.unity
                '';
            hearthstone-linux-stubs = pkgs.stdenv.mkDerivation {
              name = "hearthstone-linux-stubs";
              src = "${hearthstone-linux.src}/stubs";
              installPhase = ''
                pout="$out/Bin/Hearthstone_Data/Plugins"
                fout="$pout/System/Library/Frameworks"
                mkdir -p $fout
                mv CoreFoundation.so $fout/CoreFoundation.framework
                mv libOSXWindowManagement.so $pout
                mv libblz_commerce_sdk_plugin.so $pout
              '';
            };
            hearthstone-linux-login = pkgs.stdenv.mkDerivation {
              name = "hearthstone-linux-login";
              src = "${hearthstone-linux.src}/login";
              nativeBuildInputs = with pkgs; [ pkg-config ];
              buildInputs = with pkgs; [
                cryptopp
                webkitgtk
              ];
              installPhase = ''
                mkdir -p $out/bin
                mv login $out/bin/login
              '';
            };
            hearthstone-linux = pkgs.stdenv.mkDerivation rec {
              name = "hearthstone-linux";
              src = pkgs.fetchFromGitHub {
                owner = "0xf4b1";
                repo = name;
                rev = "d91f2f46d73081347f986fa3fe1a14716c6e6692";
                hash = "sha256-ToiZYygvt8T2iRI50oP8zAIOeIlMpxCGi73YSuwBuiI=";
              };
              region = "eu";
              buildInputs = with pkgs; [ python3 ];
              nativeBuildInputs = with pkgs; [ autoPatchelfHook ];
              buildPhase = ''
                rmdir keg
                ln -s ${keg} keg
                mkdir -p venv/bin
                touch venv/bin/activate
                mkdir -p Bin $out $out/share/applications
                ln -s Bin $out
                sed -i 's|>~/.local|>$out|; s|^        \[ -d|# |; s|^create_compatibility_files$||g; s|^\[ -f|# |' craft.sh
                sed -i '185a TARGET_PATH="$out"'  craft.sh
                echo $region > .region

                cat craft.sh
                bash ./craft.sh ${hearthstone-data-transformed} ${hearthstone-unity}
              '';
            };
          };
        };
    };
}
