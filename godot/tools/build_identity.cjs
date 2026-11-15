const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const hashFile = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function hashSources(root) {
  const hash = crypto.createHash('sha256');
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, {withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name,'en'))) {
      if (entry.name.startsWith('.') || (dir === root && entry.name === 'docs')) continue;
      const full = path.join(dir,entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile()) hash.update(path.relative(root,full).replaceAll('\\','/') + '\0' + hashFile(full) + '\n');
    }
  }
  walk(root);
  return hash.digest('hex');
}
function sourceIdentity(root) {
  const git = args => cp.execFileSync('git',args,{cwd:root,encoding:'utf8'}).trim();
  return {revision:git(['rev-parse','HEAD']),source_sha256:hashSources(root),
    dirty:!!git(['status','--porcelain','--untracked-files=all','--','.'])};
}
function readBuild(exe, currentHash, allowStale = false) {
  const build = JSON.parse(fs.readFileSync(exe + '.build.json','utf8'));
  if (build.executable_sha256 !== hashFile(exe)) throw new Error('Release executable does not match its build manifest');
  if (!/^[a-f0-9]{40}$/i.test(build.source?.revision || '') || !/^[a-f0-9]{64}$/i.test(build.source?.source_sha256 || '')) throw new Error('Invalid build source identity');
  const stale = build.source.source_sha256 !== currentHash;
  if (stale && !allowStale) throw new Error('Source changed since export; rebuild or explicitly use --allow-stale-build for comparison');
  return {...build,stale_source:stale};
}
module.exports = {hashFile,hashSources,sourceIdentity,readBuild};
