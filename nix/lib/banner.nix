{
  lib,
  pkgs,
}: {
  title,
  commands,
}: let
  width = lib.foldl' lib.max 0 (map (c: lib.stringLength c.command) commands);
  pad = s: s + lib.concatStrings (lib.genList (_: " ") (width - lib.stringLength s));
  body = pkgs.writeText "banner.txt" (lib.concatMapStrings (c: "${pad c.command}  ${c.description}\n") commands);
in
  # Printed to stderr and only for a terminal, so `nix develop -c` output stays clean in scripts.
  ''
    if [ -t 2 ]; then
      ${lib.getExe pkgs.little_boxes} --charset rounded --title ${lib.escapeShellArg title} --file ${body} >&2
    fi
  ''
