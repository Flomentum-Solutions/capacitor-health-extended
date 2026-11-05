# Node 24 Migration Summary

All configurations and documentation across the codebase have been updated to target **Node.js 24**.

## Changes Summary

1. **`package.json`**:
   - Added `"engines": { "node": ">=24.0.0" }` to formally specify Node 24+ support for consumers and package managers.
   - Normalized `"repository.url"` to `"git+https://github.com/Flomentum-Solutions/capacitor-health-extended.git"` (via `npm pkg fix`) to eliminate the npm publish warning.

2. **`package-lock.json`**:
   - Synchronized root package `engines` requirement with `package.json`.

3. **`.github/workflows/publish.yml`**:
   - Updated `actions/setup-node@v4` action step `node-version` from `'22'` to `'24'`.
   - Enabled `id-token: write` permission for npm OIDC authentication.
   - Configured `npm publish --access public --provenance` and removed static `NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}` for npm Trusted Publishing.

4. **`README.md`**:
   - Updated plugin requirements overview to **Node.js 24+**.
   - Updated Requirements section item to `- Node.js 24+ (Latest LTS version is recommended)`.

5. **Node Version Manager Configs**:
   - Created [`.nvmrc`](file:///Users/Shared/Git/capacitor-health-extended/.nvmrc) with `24`.
   - Created [`.node-version`](file:///Users/Shared/Git/capacitor-health-extended/.node-version) with `24`.

## Verification
- Ran `npm run build` cleanly (clean dist, typescript compilation, and rollup bundling).
- Verified git status and diffs across all modified and newly created files.
