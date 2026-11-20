{
  lib,
  pkgs,
}: {
  title,
  commands,
}: let
  q = lib.escapeShellArg;
  esc = builtins.fromJSON ''"\u001b"'';
  sgr = code: "${esc}[${code}m";

  width = lib.foldl' lib.max 0 (map (c: lib.stringLength c.command) commands);
  pad = s: s + lib.concatStrings (lib.genList (_: " ") (width - lib.stringLength s));

  render = colour: let
    paint = code: s:
      if colour
      then sgr code + s + sgr "0"
      else s;
  in {
    # A raw escape byte in shellHook breaks nix develop's env parsing, so the
    # title's codes come from bash $'' quoting instead.
    title =
      if colour
      then "$'\\e[1;35m'${q title}$'\\e[0m'"
      else q title;
    body = pkgs.writeText "banner.txt" (lib.concatMapStrings
      (c: "${paint "1;36" (pad c.command)}  ${paint "37" c.description}\n")
      commands);
  };

  box = r: "${lib.getExe pkgs.little_boxes} --charset rounded --title ${r.title} --file ${r.body} >&2";
in
  # Printed to stderr and only for a terminal, so `nix develop -c` output stays clean in scripts.
  ''
    if [ -t 2 ]; then
      if [ -n "''${NO_COLOR:-}" ]; then
        ${box (render false)}
      else
        ${box (render true)}
      fi
    fi
  ''
