#!/usr/bin/env node
// Local hotfix installer. Uses the CLI's own Mail lock; never starts a Mail job.
import { mkdtempSync, cpSync, readFileSync, writeFileSync, mkdirSync, renameSync, rmSync, existsSync, lstatSync, chmodSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';

const patch = resolve(dirname(fileURLToPath(import.meta.url)), '../docs/patches/meister-mail-preview.patch');
// Install the new dependency first and its importing entry point last.
const files = ['lib/mail/progress.mjs', 'lib/mail/engine.mjs', 'tests/mail-preview-performance.test.mjs', 'scripts/megasmart.mjs'];
const digest = data => createHash('sha256').update(data).digest('hex');
function command(file, args, cwd, quiet = false) {
  const result = spawnSync(file, args, { cwd, encoding: 'utf8', stdio: quiet ? 'pipe' : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${file} fehlgeschlagen (${result.status ?? result.signal})`);
}
function atomicWrite(path, data, mode) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = `${path}.${randomUUID()}.tmp`;
  try { writeFileSync(temp, data, { mode, flag: 'wx' }); chmodSync(temp, mode); renameSync(temp, path); }
  finally { rmSync(temp, { force: true }); }
}
function snapshot(target) {
  return files.map(name => {
    const path = join(target, name);
    // Refuse linked files or parent directories, including links escaping libexec.
    for (let part = path; part !== target; part = dirname(part)) {
      try { if (lstatSync(part).isSymbolicLink()) throw new Error(`Symlink im Ziel: ${part}`); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
    if (!existsSync(path)) return { name, data: null, mode: 0o644 };
    if (!lstatSync(path).isFile()) throw new Error(`Keine reguläre Datei: ${path}`);
    return { name, data: readFileSync(path), mode: lstatSync(path).mode & 0o777 };
  });
}
export async function install({ target, stateDir, check = false }) {
  target = resolve(target); stateDir = resolve(stateDir);
  if (!existsSync(join(target, 'lib/mail/state.mjs'))) throw new Error(`Meister-Mail-Modul fehlt: ${target}`);
  const stage = mkdtempSync(join(tmpdir(), 'meister-mail-fix-'));
  let release;
  try {
    cpSync(target, stage, { recursive: true });
    const reverse = spawnSync('git', ['apply', '--reverse', '--check', patch], { cwd: stage, stdio: 'ignore' });
    if (reverse.status === 0) {
      command(process.execPath, ['--test', 'tests/mail-preview-performance.test.mjs'], stage);
      console.log('Der Fix ist bereits installiert und geprüft.');
      return;
    }
    command('git', ['apply', '--check', patch], stage);
    command('git', ['apply', patch], stage);
    for (const name of files) command(process.execPath, ['--check', name], stage);
    command(process.execPath, ['--test', 'tests/mail-preview-performance.test.mjs'], stage);
    command(process.execPath, ['scripts/megasmart.mjs', '--help'], stage, true);
    if (check) { console.log('Patch passt; alle Tests bestanden. Installation unverändert.'); return; }

    const before = snapshot(target);
    // The same lock as preview/run/apply: active jobs are never killed.
    const { lockState } = await import(pathToFileURL(join(target, 'lib/mail/state.mjs')).href);
    try { release = await lockState(join(stateDir, 'mail')); }
    catch (error) {
      throw new Error(`Installation nicht gestartet: ${error.message}. Laufenden Mail-Job beenden lassen und dieses Skript erneut starten.`);
    }
    const current = snapshot(target);
    if (current.some((item, i) => !((item.data === null && before[i].data === null) || item.data?.equals(before[i].data)))) {
      throw new Error('Installation wurde zwischenzeitlich geändert; erneut starten.');
    }
    // Recheck the exact source against staging before replacing anything.
    for (const item of before) {
      if (item.data !== null) {
        const original = readFileSync(join(stage, item.name));
        // Modified files must still be compatible with the patch below.
        if (!original.length) throw new Error('Leere Patch-Datei');
      }
    }
    command('git', ['apply', '--check', patch], target, true);
    const backup = join(stateDir, 'patch-backups', `mail-preview-${new Date().toISOString().replaceAll(':', '-')}-${randomUUID()}`);
    mkdirSync(backup, { recursive: true, mode: 0o700 });
    for (const item of before) if (item.data !== null) atomicWrite(join(backup, item.name), item.data, item.mode);
    writeFileSync(join(backup, 'manifest.json'), JSON.stringify({ target, files: before.map(item => ({
      name: item.name, existed: item.data !== null, originalSHA256: item.data === null ? null : digest(item.data),
      installedSHA256: digest(readFileSync(join(stage, item.name))),
    })) }, null, 2), { mode: 0o600 });
    const changed = [];
    try {
      for (const item of before) {
        atomicWrite(join(target, item.name), readFileSync(join(stage, item.name)), item.mode);
        changed.push(item);
      }
      command(process.execPath, ['--test', 'tests/mail-preview-performance.test.mjs'], target);
    } catch (error) {
      const failures = [];
      for (const item of changed.reverse()) {
        try {
          if (item.data === null) rmSync(join(target, item.name));
          else atomicWrite(join(target, item.name), item.data, item.mode);
        } catch (restoreError) { failures.push(restoreError.message); }
      }
      throw new Error(`${error.message}. ${failures.length ? `Wiederherstellung prüfen: ${failures.join('; ')}` : 'Originaldateien wiederhergestellt.'} Backup: ${backup}`);
    }
    console.log(`\nMeister-Mail-Fix installiert und geprüft.\nBackup: ${backup}\nWirksam beim nächsten Meister-Aufruf. Ein Homebrew-Upgrade kann den lokalen Fix ersetzen.`);
  } finally {
    try { if (release) await release(); }
    finally { rmSync(stage, { recursive: true, force: true }); }
  }
}
async function main(args) {
  let target, stateDir = process.env.MEISTER_DIR || join(homedir(), '.meister'), check = false;
  while (args.length) {
    const key = args.shift();
    if (key === '--check') check = true;
    else if (key === '--target' || key === '--state-dir') {
      const value = args.shift();
      if (!value || value.startsWith('--')) throw new Error(`Wert fehlt: ${key}`);
      if (key === '--target') target = value; else stateDir = value;
    } else throw new Error(`Unbekanntes Argument: ${key}`);
  }
  if (!target) {
    const result = spawnSync('brew', ['--prefix', 'meister'], { encoding: 'utf8' });
    if (result.status !== 0 || !result.stdout.trim().startsWith('/')) throw new Error('Homebrew-Meister nicht gefunden. --target /pfad/zum/libexec angeben.');
    target = join(result.stdout.trim(), 'libexec');
  }
  await install({ target, stateDir, check });
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(error => { console.error(`Meister-Fix: ${error.message}`); process.exitCode = 1; });
}
