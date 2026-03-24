{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        chickenEggs = pkgs.chickenPackages_5.chickenEggs;

        eggs = with chickenEggs; [
          srfi-69
          matchable
        ];

        testEggs = with chickenEggs; [
          srfi-1
          test
        ];

        allEggs = eggs ++ testEggs;

        # Build the repository path, including the base Chicken installation
        mkRepoPath =
          eggList:
          let
            baseChickenRepo = "${pkgs.chicken}/lib/chicken/11";
            eggRepos = pkgs.lib.concatMapStringsSep ":" (egg: "${egg}/lib/chicken/11") eggList;
          in
          "${baseChickenRepo}:${eggRepos}";

        # Compile the extension from source
        lru-cache = pkgs.stdenv.mkDerivation {
          pname = "chicken-lru-cache";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.chicken ] ++ eggs;

          buildPhase = ''
            export CHICKEN_REPOSITORY_PATH="${mkRepoPath eggs}"
            csc -s -J -O2 -emit-types-file lru-cache.types lru-cache.scm
          '';

          installPhase = ''
            mkdir -p $out/lib/chicken/11

            cp lru-cache.so $out/lib/chicken/11/
            cp lru-cache.import.scm $out/lib/chicken/11/

            if [[ -f lru-cache.types ]]; then
              cp lru-cache.types $out/lib/chicken/11/
            fi
          '';
        };
      in
      {
        packages.default = lru-cache;

        checks.default =
          pkgs.runCommand "lru-cache-tests"
            {
              nativeBuildInputs = [ pkgs.chicken ] ++ allEggs;
            }
            ''
              export CHICKEN_REPOSITORY_PATH="${mkRepoPath allEggs}:${lru-cache}/lib/chicken/11"
              cd ${./tests}
              csi -s run.scm
              touch $out
            '';

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.chicken ] ++ allEggs;

          shellHook = ''
            export CHICKEN_REPOSITORY_PATH="${mkRepoPath allEggs}"
          '';
        };
      }
    );
}
