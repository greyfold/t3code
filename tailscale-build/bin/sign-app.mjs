// Sign a packaged Electron .app with @electron/osx-sign (already installed as an
// electron-builder dependency of the checked-out release).
// Usage: node sign-app.mjs <src-root> <app> <identity> <entitlements>
import { readdirSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [srcRoot, app, identity, entitlements] = process.argv.slice(2);
if (!srcRoot || !app || !identity || !entitlements) {
  throw new Error("usage: sign-app.mjs <src-root> <app> <identity> <entitlements>");
}

const store = join(srcRoot, "node_modules/.pnpm");
const versionOf = (dir) => dir.match(/osx-sign@(\d+)\.(\d+)\.(\d+)/).slice(1).map(Number);
const newest = readdirSync(store)
  .filter((dir) => /^@electron\+osx-sign@\d+\.\d+\.\d+/.test(dir))
  .sort((a, b) => {
    const [x, y] = [versionOf(a), versionOf(b)];
    return y[0] - x[0] || y[1] - x[1] || y[2] - x[2];
  })[0];
if (!newest) throw new Error(`@electron/osx-sign not found under ${store}`);

// Importing the package directory by name lets Node apply the package's own
// entry points, whatever its dist layout is in this version.
const require = createRequire(join(store, newest, "node_modules/package.json"));
const { sign } = await import(pathToFileURL(require.resolve("@electron/osx-sign")).href);

await sign({
  app,
  identity,
  platform: "darwin",
  batchCodesignCalls: true,
  optionsForFile: () => ({ hardenedRuntime: true, entitlements }),
});
console.log(`signed with ${newest}: ${app}`);
