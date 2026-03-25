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

        docEggs = with chickenEggs; [
          svnwiki-sxml
          sxml-transforms
          html-parser
          matchable
          srfi-1
          srfi-13
          srfi-14
          regex
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

        # Convert svnwiki documentation to GitHub-flavoured Markdown
        generate-readme = pkgs.writeShellApplication {
          name = "generate-readme";
          runtimeInputs = [
            pkgs.chicken
            pkgs.pandoc
          ];
          text = ''
            export CHICKEN_REPOSITORY_PATH="${mkRepoPath docEggs}"
            input="''${1:?Usage: generate-readme <input.wiki>}"
            {
              echo "<!-- DO NOT EDIT: generated from $input by generate-readme -->"
              echo
              csi -s ${./scripts/wiki2html.scm} "$input" | pandoc -f html -t gfm
            }
          '';
        };

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
        packages.generate-readme = generate-readme;

        apps.generate-readme = {
          type = "app";
          program = "${generate-readme}/bin/generate-readme";
        };

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
