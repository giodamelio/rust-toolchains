_: {
  perSystem = {
    lib,
    pkgs,
    ...
  }: {
    formatter = lib.mkDefault pkgs.alejandra;
  };
}
