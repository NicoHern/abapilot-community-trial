import { chmod, copyFile, mkdir } from "node:fs/promises";

const root = new URL("./", import.meta.url);
const dist = new URL("dist/", root);
await mkdir(dist, { recursive: true });
for (const file of ["index.js", "lib.mjs"]) {
  await copyFile(new URL(file, root), new URL(file, dist));
}
await chmod(new URL("index.js", dist), 0o755);
await copyFile(new URL("../README.md", root), new URL("README.md", root));
await copyFile(new URL("../LICENSE", root), new URL("LICENSE", root));
