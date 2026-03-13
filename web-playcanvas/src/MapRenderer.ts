import * as pc from "playcanvas";

// Same level data as server
const LEVEL = [
  [13.5, 2, 1, 4], [13.5, 12, 1, 2], [12.5, 13.5, 3, 1], [2, 13.5, 4, 1],
  [11.5, 15, 1, 2], [11.5, 23.5, 1, 5],
  [10, 26.5, 4, 1], [6, 26.5, 4, 1],
  [2, 34.5, 4, 1], [12.5, 34.5, 3, 1], [13.5, 36, 1, 2], [15, 36.5, 2, 1],
  [13.5, 46, 1, 4],
  [23.5, 36.5, 5, 1], [26.5, 38, 1, 4], [26.5, 42, 1, 4],
  [34.5, 46, 1, 4], [34.5, 36, 1, 2], [35.5, 34.5, 3, 1], [36.5, 33, 1, 2],
  [46, 34.5, 4, 1],
  [36.5, 24.5, 1, 5], [38, 21.5, 4, 1], [42, 21.5, 4, 1],
  [46, 13.5, 4, 1], [35.5, 13.5, 3, 1], [34.5, 12, 1, 2], [33, 11.5, 2, 1],
  [34.5, 2, 1, 4],
  [24.5, 11.5, 5, 1], [21.5, 10, 1, 4], [21.5, 6, 1, 4],
  // center
  [18.5, 22, 1, 6], [19, 18.5, 2, 1], [26, 18.5, 6, 1], [29.5, 19, 1, 2],
  [29.5, 26, 1, 6], [29, 29.5, 2, 1], [22, 29.5, 6, 1], [18.5, 29, 1, 2],
];

export class MapRenderer {
  root: pc.Entity;

  constructor(private app: pc.AppBase) {
    this.root = new pc.Entity("map");
    this.buildGround();
    this.buildBlocks();
    this.buildBoundary();
    app.root.addChild(this.root);
  }

  private buildGround() {
    // Floor: vertex-colored gradient (white north → soft blue south)
    const segsX = 1;
    const segsZ = 48;
    const cols = segsX + 1;
    const rows = segsZ + 1;
    const vertCount = cols * rows;

    const positions: number[] = new Array(vertCount * 3).fill(0);
    const normals: number[] = new Array(vertCount * 3).fill(0);
    const colors = new Uint8ClampedArray(vertCount * 4);
    const indices: number[] = [];

    for (let iz = 0; iz < rows; iz++) {
      for (let ix = 0; ix < cols; ix++) {
        const vi = iz * cols + ix;
        const x = (ix / segsX - 0.5) * 48;
        const z = (iz / segsZ - 0.5) * 48;

        positions[vi * 3] = x;
        positions[vi * 3 + 1] = 0;
        positions[vi * 3 + 2] = z;

        normals[vi * 3] = 0;
        normals[vi * 3 + 1] = 1;
        normals[vi * 3 + 2] = 0;

        // Gradient: t=0 at north edge, t=1 at south edge
        const t = iz / segsZ;
        const r = 0.92 - t * 0.72;
        const g = 0.94 - t * 0.59;
        const b = 0.96 - t * 0.36;
        colors[vi * 4] = Math.round(r * 255);
        colors[vi * 4 + 1] = Math.round(g * 255);
        colors[vi * 4 + 2] = Math.round(b * 255);
        colors[vi * 4 + 3] = 255;
      }
    }

    for (let iz = 0; iz < segsZ; iz++) {
      for (let ix = 0; ix < segsX; ix++) {
        const a = iz * cols + ix;
        const b = a + 1;
        const c = a + cols;
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }

    const mesh = new pc.Mesh(this.app.graphicsDevice);
    mesh.setPositions(positions);
    mesh.setNormals(normals);
    mesh.setColors32(colors);
    mesh.setIndices(indices);
    mesh.update(pc.PRIMITIVE_TRIANGLES);

    const mat = new pc.StandardMaterial();
    mat.diffuseVertexColor = true;
    mat.diffuse = pc.Color.WHITE;
    mat.gloss = 0.6;
    mat.metalness = 0.05;
    mat.useMetalness = true;
    mat.update();

    const mi = new pc.MeshInstance(mesh, mat);
    const ground = new pc.Entity("ground");
    ground.addComponent("render", {
      type: "asset",
      meshInstances: [mi],
      castShadows: false,
    });
    ground.setLocalPosition(24, -0.01, 24);
    this.root.addChild(ground);
  }

  private buildBlocks() {
    const blockMat = new pc.StandardMaterial();
    blockMat.diffuse = new pc.Color(0.133, 0.4, 0.667);
    blockMat.gloss = 0.7;
    blockMat.metalness = 0.2;
    blockMat.useMetalness = true;
    blockMat.opacity = 0.85;
    blockMat.blendType = pc.BLEND_NORMAL;
    blockMat.update();

    for (const [bx, by, bw, bh] of LEVEL) {
      const block = new pc.Entity("block");
      block.addComponent("render", {
        type: "box",
        material: blockMat,
        castShadows: true,
      });
      block.setLocalPosition(bx, 0.6, by);
      block.setLocalScale(bw, 1.2, bh);
      this.root.addChild(block);
    }
  }

  private buildBoundary() {
    const thickness = 1.5;
    const height = 2.0;

    const wallMat = new pc.StandardMaterial();
    wallMat.diffuse = new pc.Color(0.102, 0.267, 0.533);
    wallMat.gloss = 0.7;
    wallMat.metalness = 0.3;
    wallMat.useMetalness = true;
    wallMat.opacity = 0.8;
    wallMat.blendType = pc.BLEND_NORMAL;
    wallMat.update();

    const walls: [number, number, number, number][] = [
      // [posX, posZ, sizeX, sizeZ]
      [24, -thickness / 2, 48 + thickness * 2, thickness],
      [24, 48 + thickness / 2, 48 + thickness * 2, thickness],
      [-thickness / 2, 24, thickness, 48 + thickness * 2],
      [48 + thickness / 2, 24, thickness, 48 + thickness * 2],
    ];

    for (const [x, z, sx, sz] of walls) {
      const wall = new pc.Entity("wall");
      wall.addComponent("render", {
        type: "box",
        material: wallMat,
        castShadows: true,
      });
      wall.setLocalPosition(x, height / 2, z);
      wall.setLocalScale(sx, height, sz);
      this.root.addChild(wall);
    }
  }
}
