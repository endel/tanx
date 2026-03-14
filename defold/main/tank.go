embedded_components {
  id: "body"
  type: "sprite"
  data: "default_animation: \"white\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/gfx/game.atlas\"\n"
  "}\n"
  position {
    x: 0.0
    y: 0.0
    z: 0.0
  }
  scale {
    x: 16.0
    y: 22.0
    z: 1.0
  }
}
embedded_components {
  id: "turret"
  type: "sprite"
  data: "default_animation: \"white\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/gfx/game.atlas\"\n"
  "}\n"
  position {
    x: 0.0
    y: 8.0
    z: 0.1
  }
  scale {
    x: 6.0
    y: 16.0
    z: 1.0
  }
}
embedded_components {
  id: "ring"
  type: "sprite"
  data: "default_animation: \"white\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/gfx/game.atlas\"\n"
  "}\n"
  position {
    x: 0.0
    y: 0.0
    z: -0.1
  }
  scale {
    x: 20.0
    y: 20.0
    z: 1.0
  }
}
