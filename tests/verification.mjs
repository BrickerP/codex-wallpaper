import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, cpSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { summarizeVerification, formatSummary } from '../skill/codex-wallpaper/scripts/verification-summary.mjs';

const repo = dirname(dirname(fileURLToPath(import.meta.url)));
const version = '1.5.20';
const revision = '1234567890abcdef1234';
const options = { exitCode: 2, engineVersion: version, expectedThemeId: 'theme-a' };
const renderer = () => ({
  installed: true, version, pass: true, themeId: 'theme-a', expectedThemeId: 'theme-a',
  stylePresent: true, businessClassPollution: 0,
  revision, expectedRevision: revision, documentVisibility: 'visible',
  nativeWindow: { status: 'unsupported' },
  checks: { documentVisible: true, fallbackWindowPass: true, nativeWindowPass: false,
    payloadPass: true, structurePass: true, viewportPass: true, windowPass: true },
});
const report = (...results) => ({ mode: 'verify', version,
  targets: results.map((result, index) => ({ targetId: `page-${index}`, result })) });
const assess = (value, overrides = {}) => summarizeVerification(JSON.stringify(value), { ...options, ...overrides });
const structure = renderer();
structure.pass = false;
structure.checks.structurePass = false;
assert.equal(assess(report(structure)).category, 'structure-failed', 'same ID does not imply a payload mismatch');
const hidden = renderer();
hidden.pass = false;
hidden.documentVisibility = 'hidden';
hidden.checks.documentVisible = hidden.checks.windowPass = false;
assert.equal(assess(report(hidden)).category, 'hidden-only');
assert.equal(assess(report(hidden)).accepted, true);
assert.equal(assess(report(hidden), { exitCode: 1 }).accepted, false);
assert.equal(assess(report(hidden, renderer())).accepted, false, 'hidden exception stays single-target');
assert.equal(assess(report({ ...hidden, checks: { ...hidden.checks, structurePass: false } })).accepted, false);
for (const [name, changes] of [
  ['ready native window', { nativeWindow: { status: 'ready' } }],
  ['not-ready native window', { nativeWindow: { status: 'not-ready' } }],
  ['missing native window', { nativeWindow: undefined }],
  ['old renderer version', { version: '1.5.12' }],
  ['missing stylesheet', { stylePresent: false }],
  ['missing stylesheet evidence', { stylePresent: undefined }],
  ['business class pollution', { businessClassPollution: 99 }],
  ['missing pollution evidence', { businessClassPollution: undefined }],
]) {
  const summary = assess(report({ ...hidden, ...changes }));
  assert.equal(summary.accepted, false, `hidden exception rejects ${name}`);
  assert.notEqual(summary.category, 'hidden-only', `${name} must not be hidden-only`);
}
const wrongId = { ...renderer(), themeId: 'theme-b', pass: false };
const wrongRevision = { ...renderer(), revision: 'aaaaaaaaaaaaaaaaaaaa', pass: false };
for (const mismatch of [wrongId, wrongRevision]) {
  assert.equal(assess(report(mismatch)).category, 'payload-mismatch');
  assert.equal(assess(report({ ...mismatch, pass: true }), { exitCode: 0 }).accepted, false);
}
assert.equal(assess(report(renderer(), structure), { exitCode: 0 }).accepted, false, 'one failure blocks all-target success');
assert.equal(assess(report(renderer(), renderer()), { exitCode: 0 }).accepted, true);
assert.equal(assess(report(renderer())).category, 'engine-error');
assert.equal(assess(report()).category, 'no-targets');
assert.equal(summarizeVerification('not JSON', options).accepted, false);
assert.equal(assess(report({ ...renderer(), expectedRevision: null }), { exitCode: 0 }).accepted, false);
assert.equal(assess(report(renderer(), { ...renderer(), expectedRevision: 'aaaaaaaaaaaaaaaaaaaa' }), { exitCode: 0 }).accepted, false);
const native = renderer();
native.pass = false;
native.checks.fallbackWindowPass = native.checks.windowPass = false;
native.nativeWindow.status = 'not-ready';
assert.equal(assess(report(native)).category, 'native-window-unverified');
assert.equal(assess(report({ ...renderer(), nativeWindow: null }), { exitCode: 0 }).category, 'native-window-unverified');
assert.equal(assess(report({ ...renderer(), documentVisibility: 'unknown' }), { exitCode: 0 }).accepted, false);
const privateError = report(null);
privateError.targets[0].error = 'PRIVATE_ERROR /Users/example/secret.png';
assert.equal(assess(privateError).accepted, false);
assert.doesNotMatch(formatSummary(assess(privateError)), /PRIVATE_ERROR|secret.png/);

const root = mkdtempSync(join(tmpdir(), 'wallpaper-verification-'));
try {
  const home = join(root, 'home');
  const engine = join(home, '.codex/codex-dream-skin-studio');
  const active = join(home, 'Library/Application Support/CodexDreamSkinStudio/theme');
  mkdirSync(join(engine, 'scripts'), { recursive: true });
  mkdirSync(active, { recursive: true });
  writeFileSync(join(engine, 'VERSION'), `${version}\n`);
  writeFileSync(join(active, 'theme.json'), JSON.stringify({ id: 'theme-a', name: 'Example' }));
  const fixture = join(root, 'fixture.json');
  const calls = join(root, 'calls');
  writeFileSync(join(engine, 'scripts/injector.mjs'), `
    import { readFileSync, appendFileSync } from 'node:fs';
    const mode = process.argv.includes('--once') ? 'once' : 'verify';
    appendFileSync(process.env.TEST_CALLS, mode + '\\n');
    const raw = readFileSync(process.env.TEST_FIXTURE, 'utf8');
    if (mode === 'once') {
      const value = JSON.parse(raw); value.mode = mode; console.log(JSON.stringify(value));
    } else console.log(raw);
    console.error('PRIVATE_ERROR /Users/example/secret.png');
    process.exit(Number(process.env.TEST_EXIT_CODE));
  `);
  const source = join(repo, 'skill/codex-wallpaper/scripts/codex-wallpaper.zsh');
  const run = (command, value, exitCode = 2, portCode = 0) => {
    writeFileSync(fixture, typeof value === 'string' ? value : JSON.stringify(value));
    writeFileSync(calls, '');
    const result = spawnSync('/bin/zsh', ['-c', `
      export CODEX_WALLPAPER_SOURCE_ONLY=1
      source "$1"
      discover_upstream_runtime() { NODE="$TEST_NODE"; }
      validate_cdp_listener() { return "$TEST_PORT_CODE"; }
      NODE="$TEST_NODE"
      "$2"
    `, '_', source, command], { encoding: 'utf8', env: { ...process.env, HOME: home,
      TEST_NODE: process.execPath, TEST_FIXTURE: fixture, TEST_CALLS: calls,
      TEST_EXIT_CODE: String(exitCode), TEST_PORT_CODE: String(portCode) } });
    assert.doesNotMatch(result.stdout + result.stderr, /PRIVATE_ERROR|secret.png/);
    return { ...result, calls: readFileSync(calls, 'utf8') };
  };
  const status = run('show_status', report(structure));
  assert.equal(status.status, 1);
  assert.match(status.stdout, /structure-failed/);
  assert.match(status.stdout, new RegExp(`当前保存身份：theme-a / revision=${revision}`));
  assert.match(status.stdout, new RegExp(`实时目标 1：theme-a / revision=${revision}`));
  assert.equal(status.calls, 'verify\n', 'status performs read-only verification');
  assert.equal(run('show_status', report(hidden)).status, 0);
  assert.equal(run('show_status', report(renderer()), 0).status, 0);
  assert.equal(run('show_status', report(renderer(), structure), 0).status, 1);
  assert.equal(run('show_status', report(), 0).status, 1);
  assert.equal(run('show_status', 'not JSON', 0).status, 1);
  const noPort = run('show_status', report(renderer()), 0, 10);
  assert.equal(noPort.status, 0);
  assert.match(noPort.stdout, /未开启/);
  assert.equal(noPort.calls, '');
  const unsafePort = run('show_status', report(renderer()), 0, 20);
  assert.equal(unsafePort.status, 1);
  assert.equal(unsafePort.calls, '');
  const injected = run('inject_active_once', report(hidden));
  assert.equal(injected.status, 0);
  assert.equal(injected.calls, 'once\nverify\n', 'hidden one-shot must still pass separate verification');
  const failedInjection = run('inject_active_once', report(structure));
  assert.equal(failedInjection.status, 1);
  assert.match(failedInjection.stderr, /structure-failed/);
  assert.equal(run('inject_active_once', report(renderer(), structure), 0).status, 1);

  const copiedSkill = join(root, 'skill');
  cpSync(join(repo, 'skill/codex-wallpaper'), copiedSkill, { recursive: true });
  writeFileSync(join(copiedSkill, '.codex-wallpaper-managed'), 'managed-by-codex-wallpaper\n');
  writeFileSync(join(engine, 'VERSION'), '1.5.12\n');
  const old = spawnSync('/bin/zsh', [join(copiedSkill, 'scripts/codex-wallpaper.zsh'), 'apply', 'theme-a'],
    { encoding: 'utf8', env: { ...process.env, HOME: home } });
  assert.notEqual(old.status, 0);
  assert.match(old.stderr, /变更要求 Dream Skin 1\.5\.20；当前为 1\.5\.12/);
  const unsupported = run('show_status', report(renderer()), 0);
  assert.equal(unsupported.status, 0);
  assert.equal(unsupported.calls, '');
  assert.match(unsupported.stdout, /实时主题：未验证/);
} finally {
  rmSync(root, { recursive: true, force: true });
}
console.log('verification diagnostics and public status: ok');
