# gaea-plugin-hairdeck

[HairDeck](https://github.com/hyz317/HairDeck) (Apache-2.0) as a [Gaea](https://github.com/xocialize-code/gaea) plugin:
anime-style hair for an avatar from one character picture, on MES `mesh.generate_part`. It is built on
[GaeaPluginKit](https://github.com/xocialize-code/gaea-plugin-kit) over
[mlx-hairdeck-swift](https://github.com/xocialize/mlx-hairdeck-swift), with
[mlx-birefnet-swift](https://github.com/xocialize/mlx-birefnet-swift) cutting the character out of an opaque picture.

Needs Gaea 1.7.0 or later. Add it by its repo URL:

```bash
gaea plugins add https://github.com/xocialize-code/gaea-plugin-hairdeck
```

**Built with DINOv3.** HairDeck's image conditioner is Meta's DINOv3, under the DINOv3 License, which asks for those
words wherever it ships. The offer carries them as the licence's `attribution`; Gaea writes them into every item
(`asset.copyright`, `asset.extras.mes.attribution`) and preview.

## What it offers

One model, `hairdeck`, on `mesh.generate_part`, in one lane (`fp32`):

- **inputs** `image` (the character) and `body` (the `.vrm` or rigged `.glb` the hair goes on: it needs a face mesh
  and a humanoid head bone);
- **`subject_box`**, required: the box around all of the hair and the face, as shares of the upright picture.
  HairDeck does not find the head itself; it squares the box and adds its own margin. It is forgiving: a box 15 % larger, 10 % smaller or shifted by 8 % changes the hair
  less than another seed does (AB-R-0851);
- **`physics`** (default true): chain bones and `VRMC_springBone`; **`texture`** `atlas` (per-card colours) or `none`;
- **`background`**: `alpha` for a picture with transparency (its alpha is the matte), `remove` for an opaque one
  (BiRefNet, a companion model prepared with HairDeck);
- **`seed`**: the same picture, box, body and seed give the same GLB, byte for byte, on the same Mac and build;
- **the result**: a hair item GLB in the body's coordinates — a skinned mesh, a small colour texture, a head bone named
  as the body's, chain bones, springs. Gaea stamps and previews it and never moves or rescales it. Merging it into
  the avatar is the client's step (Item Studio's `mergeVrm`).

About a second a hairstyle once loaded. HairDeck is charged 5.5 GB (measured: 4.4 GB peak in MLX, 5.2 GB in the
process), and BiRefNet, prepared with it, its own lane's charge on top.

## Weights

Gaea sends its models root in `configure`. HairDeck reads `xocialize/hairdeck-mlx` (five files, 1.6 GB) and
`dino.safetensors` of `xocialize/trellis2-mlx` (1.2 GB, shared with the TRELLIS.2 plugin), BiRefNet
`mlx-community/BiRefNet-fp16`, in MLXEngine's store layout; all are downloaded on first use when missing.

## Build and check locally

```bash
scripts/build-plugin.sh
```

```bash
GOLDEN_IMAGE=cutout.png GOLDEN_BODY=body.vrm GOLDEN_BOX='{"x":0.09,"y":0.06,"width":0.82,"height":0.82}' scripts/golden.sh out/golden
```

`golden.sh` makes one hair item over GPP on the signed bundle and one through `hairdeck-inproc` (the same packages
in-process through MLXServeEngine) and needs them to be the same file. `scripts/check-plugin.sh` drives the bundle with
GaeaPluginKit's `gaea-plugin-check` with every `.build` folder hidden, on `Tests/Fixtures/girl.png` (an original
character made with Z-Image Turbo through Gaea, cut out) and the body named by `CHECK_BODY`. `scripts/release.sh`
builds, checks, notarizes and publishes the GitHub release; the release workflow is the template's and has not run.

## Licence

The plugin is Apache-2.0 (Gaea G-21). HairDeck's code and weights are Apache-2.0; the port, mlx-hairdeck-swift, is MIT.
Its DINOv3 conditioner is under Meta's [DINOv3 License](https://ai.meta.com/resources/models-and-libraries/dinov3-license/)
("Built with DINOv3"). BiRefNet is MIT.
