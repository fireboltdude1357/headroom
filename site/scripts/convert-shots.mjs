// Copies the app screenshots into public/shots as WebP, downscaled to a sensible web size.
import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const source = new URL("../../dist/screenshots/", import.meta.url);
const target = new URL("../public/shots/", import.meta.url);
await mkdir(target, { recursive: true });

// [name, max width in px]. Window shots are 2200 wide at 2x; 1600 is plenty for a 800pt column at 2x.
const shots = [
  ["overview", 1600], ["projects", 1600], ["category-expanded", 1600], ["trash", 1600],
  ["review", 1120], ["menubar", 640],
];

for (const [name, width] of shots) {
  for (const mode of ["light", "dark"]) {
    const file = `${name}-${mode}`;
    const info = await sharp(fileURLToPath(new URL(`${file}.png`, source)))
      .resize({ width, withoutEnlargement: true })
      .webp({ quality: 82 })
      .toFile(fileURLToPath(new URL(`${file}.webp`, target)));
    console.log(file, info.width, "x", info.height, Math.round(info.size / 1024), "KB");
  }
}
