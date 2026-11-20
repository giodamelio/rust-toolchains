{
  lib,
  rustPlatform,
  fetchCrate,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "skills-cli";
  version = "0.7.0";

  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-5UhJ96JzrQMwBGXwZXmucYhDsvReQEcR1mM104a8NwA=";
  };

  cargoHash = "sha256-8E6r8fdEzRIYflbIr+/9jKl2RwEr719Nx/037WtZ2xg=";

  # skills-cli hardwires the skill library's telemetry feature, which posts
  # usage events to add-skill.vercel.sh. Without it, telemetry::track is a no-op.
  postPatch = ''
    substituteInPlace Cargo.toml --replace-fail '"telemetry",' ""
  '';

  meta = {
    description = "Rust port of the Vercel Skills CLI for installing agent skills";
    homepage = "https://github.com/qntx/skill";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "skills";
  };
})
