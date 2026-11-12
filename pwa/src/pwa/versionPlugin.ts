import { execSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import type { Plugin } from 'vite';

/**
 * Writes `version.json` — `{ version, builtAt, commit }` — into the build
 * output, so the app can show which build it is running and the service
 * worker's precache manifest changes with every build even when no file
 * else did. The dev server answers the same path with the package version
 * and `builtAt: "dev"`.
 *
 * It writes in `writeBundle`, which runs before vite-plugin-pwa's
 * `closeBundle` globs the output for the precache manifest, so the file is
 * precached with the rest.
 *
 *   plugins: [preact(), versionPlugin(), VitePWA({ … })]
 */
export interface VersionPluginOptions {
  /** Overrides the version read from package.json. */
  version?: string;
  /** The file name under the output directory. Default `version.json`. */
  fileName?: string;
}

export function versionPlugin(options: VersionPluginOptions = {}): Plugin {
  const fileName = options.fileName ?? 'version.json';
  let outDir = 'dist';
  let root = process.cwd();
  // Computed once per process: vite-plugin-pwa runs a second build for the
  // worker, and the file must not change after the precache manifest has
  // recorded its hash.
  let cached: { version: string; builtAt: string; commit?: string } | null = null;
  const read = (): { version: string; builtAt: string; commit?: string } => {
    if (cached) return cached;
    let version = options.version;
    if (!version) {
      try {
        version = (JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')) as { version?: string }).version;
      } catch {
        // No package.json where expected.
      }
    }
    cached = { version: version ?? '0.0.0', builtAt: new Date().toISOString(), commit: commitHash(root) };
    return cached;
  };
  return {
    name: 'openword:version',
    configResolved(config) {
      root = config.root;
      outDir = config.build.outDir;
    },
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if ((req.url ?? '').split('?')[0] !== `/${fileName}`) return next();
        res.setHeader('content-type', 'application/json');
        res.setHeader('cache-control', 'no-store');
        res.end(JSON.stringify({ ...read(), builtAt: 'dev' }));
      });
    },
    writeBundle() {
      const dir = resolve(root, outDir);
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, fileName), `${JSON.stringify(read(), null, 2)}\n`);
    },
  };
}

function commitHash(cwd: string): string | undefined {
  try {
    return execSync('git rev-parse --short HEAD', { cwd, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() || undefined;
  } catch {
    return undefined;
  }
}
