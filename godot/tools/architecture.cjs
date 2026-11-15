const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const ROOT = path.resolve(__dirname, '..');
const MANIFEST = 'docs/architecture/modules.json';
const PURE_FORBIDDEN = ['FileAccess', 'DirAccess', 'ResourceLoader', 'ResourceSaver', 'Input', 'SceneTree', 'RenderingServer', 'AudioServer', 'DisplayServer', 'ProjectSettings', 'ClassDB', 'GDExtensionManager', 'Engine', 'OS', 'Time', 'JavaScriptBridge', 'get_tree', 'Node', 'Node2D', 'Node3D', 'Control', 'CanvasItem', 'Sprite2D', 'CharacterBody2D', 'NavigationAgent2D', 'AnimationPlayer', 'PackedScene', 'Resource'];
const NATIVE_SUFFIX = /\.(cpp|hpp|h)$/;
const ASSET_SUFFIX = /\.(png|jpe?g|svg|webp|ogg|wav|mp3|ttf|otf|json|res|gdextension|tscn|tres)$/;
const REFERENCED_SUFFIX = /\.(gd|tscn|tres|cpp|hpp|h|gdextension|png|jpe?g|svg|webp|ogg|wav|mp3|ttf|otf|json|res)$/;
const NATIVE_VALUE_HEADERS = new Set(['algorithm','array','cmath','cstddef','cstdint','cstring','limits','numeric','tuple','type_traits','utility','vector']);

// A file entry grants exactly that file, not similarly named internal scripts.
const covers = (file, entry) => entry.endsWith('/') ? file.startsWith(entry) : file === entry;
const ignoredSourceIssues = paths => paths.filter(Boolean).map(file => `Source/inventory file is ignored by Git: ${file}`);
function manifestIssues(manifest) {
  const errors = [], names = new Set(), prefixes = [];
  const safe = p => typeof p === 'string' && p.length > 0 && !p.startsWith('/') && !p.includes('\\') && !p.includes(':') && !p.split('/').some(s => s === '..' || s === '.');
  for (const m of manifest.modules) {
    if (!m.name || names.has(m.name)) errors.push(`Duplicate/missing module name: ${m.name}`);
    names.add(m.name);
    if (!m.owner || typeof m.owner !== 'string') errors.push(`Missing module owner: ${m.name}`);
    if (!safe(m.prefix) || !m.prefix.endsWith('/')) errors.push(`Invalid module prefix: ${m.name}`);
    else {
      for (const p of prefixes) if (m.prefix.startsWith(p) || p.startsWith(m.prefix)) errors.push(`Overlapping module prefixes: ${p}, ${m.prefix}`);
      prefixes.push(m.prefix);
    }
    for (const entry of m.public) if (!safe(entry) || !entry.startsWith(m.prefix)) errors.push(`Public entry outside module: ${m.name}: ${entry}`);
    if (new Set(m.allowed).size !== m.allowed.length) errors.push(`Duplicate allowed dependency: ${m.name}`);
  }
  for (const m of manifest.modules) for (const name of m.allowed) if (!names.has(name) || name === m.name) errors.push(`Invalid allowed dependency: ${m.name} -> ${name}`);
  return errors;
}

function contractChangeIssues(changed, contractChanged) {
  if (!contractChanged) return [];
  const errors = [];
  if (!changed.some(p => /^docs\/architecture\/ADR-[^/]+\.md$/.test(p))) errors.push('Architecture contract change requires an updated ADR');
  if (!changed.some(p => /^tools\/architecture\.test\.cjs$|^tests\/.+\.(gd|cjs)$/.test(p))) errors.push('Architecture contract change requires updated executable checks');
  return errors;
}

// Tokenize strings/comments separately: imports in comments are not dependencies,
// and identifiers inside strings are not executable calls. Both quote styles work.
function tokens(source) {
  const result = [];
  let line = 1, previous = 0;
  const re = /#[^\n]*|"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|[^\s]/g;
  for (const match of source.matchAll(re)) {
    line += (source.slice(previous,match.index).match(/\n/g) || []).length;
    previous = match.index;
    const value = match[0];
    if (value.startsWith('#')) continue;
    result.push({ value: /^['"]/.test(value) ? value.slice(value.startsWith('"""') || value.startsWith("'''") ? 3 : 1, value.startsWith('"""') || value.startsWith("'''") ? -3 : -1) : value,
      string: /^['"]/.test(value), line });
  }
  return result;
}

function collect(root) {
  const files = new Map();
  function walk(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name.startsWith('.')) continue;
      if (dir === root && e.name === 'docs') continue;
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full);
      else if (/\.(gd|tscn|tres|uid|cpp|hpp|h|gdextension|json|import)$/.test(e.name)) files.set(path.relative(root, full).replaceAll('\\', '/'), fs.readFileSync(full, 'utf8'));
      else if (ASSET_SUFFIX.test(e.name)) files.set(path.relative(root, full).replaceAll('\\', '/'), '');
    }
  }
  walk(root);
  return files;
}

function analyze(files, manifest) {
  const issues = [];
  const graph = new Map(), classes = new Map(), uids = new Map();
  const parsed = new Map();
  const nativeIncludes = new Map();
  const impure = new Set();
  const isPure = file => ['core/','runtime/',...(manifest.purePrefixes || [])].some(prefix => file.startsWith(prefix));
  const test = p => p.startsWith('tests/') || p.includes('/tests/') || p.startsWith('tools/') || p.includes('/tools/');
  const owner = p => manifest.modules.find(m => p.startsWith(m.prefix));
  const add = (file, rule, target) => issues.push({ file, rule, target, key: `${file}|${rule}|${target}` });
  for (const [file, source] of files) {
    if (file.endsWith('.import')) {
      const uid = source.match(/^uid="(uid:\/\/[^\"]+)"/m)?.[1];
      if (uid) {
        if (uids.has(uid)) add(file,'duplicate-uid',uid);
        uids.set(uid,file.slice(0,-7));
      }
      continue; // Import cache paths are generated artifacts, not source dependencies.
    }
    if (file.endsWith('.uid')) {
      if (uids.has(source.trim())) add(file, 'duplicate-uid', source.trim());
      uids.set(source.trim(), file.slice(0, -4)); continue;
    }
    if (/\.(tscn|tres)$/.test(file)) {
      const resourceUid = source.match(/^\[(?:gd_scene|gd_resource)\b[^\]\n]*\buid="(uid:\/\/[^\"]+)"/);
      if (resourceUid) {
        if (uids.has(resourceUid[1])) add(file, 'duplicate-uid', resourceUid[1]);
        uids.set(resourceUid[1], file);
      }
    }
    let codeSource = source;
    if (ASSET_SUFFIX.test(file)) {
      impure.add(file);
      if (isPure(file) && !test(file)) add(file,'pure-core','engine/content resource');
    }
    if (NATIVE_SUFFIX.test(file)) {
      codeSource = source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g,'');
      const imports = [...codeSource.matchAll(/^\s*#\s*include\s*(["<])([^">]+)[">]/gm)].map(m=>({local:m[1]==='"',path:m[2]}));
      nativeIncludes.set(file,imports);
      for (const match of codeSource.matchAll(/\bGDCLASS\s*\(\s*(\w+)\s*,/g)) {
        if (classes.has(match[1])) add(file,'duplicate-class',match[1]);
        classes.set(match[1],file);
      }
      if (imports.some(i=>!i.local && !NATIVE_VALUE_HEADERS.has(i.path)) || /\bgodot\s*::|\bnamespace\s+godot\b/.test(codeSource)) impure.add(file);
      if (isPure(file) && !test(file)) {
        for (const i of imports) if (!i.local && !NATIVE_VALUE_HEADERS.has(i.path)) add(file,'native-purity',i.path);
        if (/\bgodot\s*::|\bnamespace\s+godot\b/.test(codeSource)) add(file,'native-purity','godot namespace');
        if (/\bstatic\s+(?!const\b|constexpr\b)[^;{}()]*[;={]/.test(codeSource)) add(file,'mutable-static','native state');
      }
    }
    const ts = tokens(codeSource); parsed.set(file, ts);
    const code = ts.filter(t => !t.string).map(t => t.value).join(' ');
    if (ts.some(t=>!t.string && PURE_FORBIDDEN.includes(t.value)) || /\b(?:static var|load\s*\()/.test(code) || /\bextends\s+(Node\w*|Control|Resource|CharacterBody\w*|RigidBody\w*|Sprite\w*|Canvas\w*|AudioStream\w*)\b/.test(code)) impure.add(file);
    for (let i = 0; i < ts.length - 1; i++) if (!ts[i].string && ts[i].value === 'class_name') {
      if (classes.has(ts[i + 1].value)) add(file, 'duplicate-class', ts[i + 1].value);
      classes.set(ts[i + 1].value, file);
    }
  }
  for (const [file, ts] of parsed) {
    for (const prefix of manifest.forbiddenPaths || []) if (covers(file, prefix)) add(file, 'retired-path', prefix);
    const dependencies = new Set();
    for (const imported of nativeIncludes.get(file) || []) {
      if (!imported.local) continue;
      const dependency = path.posix.normalize(path.posix.join(path.posix.dirname(file),imported.path));
      if (!files.has(dependency)) add(file,'missing-reference',dependency);
      else dependencies.add(dependency);
    }
    for (const t of ts) {
      let dependency;
      if (t.string && t.value.startsWith('res://')) dependency = path.posix.normalize(t.value.slice(6));
      else if (t.string && t.value.startsWith('uid://')) dependency = uids.get(t.value);
      else if (!t.string && classes.has(t.value)) dependency = classes.get(t.value);
      else if (t.string && classes.has(t.value) && NATIVE_SUFFIX.test(classes.get(t.value))) dependency = classes.get(t.value);
      else if (t.string && /^(\.\.?\/)/.test(t.value) && REFERENCED_SUFFIX.test(t.value)) dependency = path.posix.normalize(path.posix.join(path.posix.dirname(file), t.value));
      if (dependency && dependency !== file && REFERENCED_SUFFIX.test(dependency)) {
        if (!files.has(dependency)) add(file, 'missing-reference', dependency);
        else dependencies.add(dependency);
      }
      if (t.string && t.value.startsWith('uid://') && !uids.has(t.value)) add(file, 'unknown-uid', t.value);
    }
    graph.set(file, dependencies);
    if (test(file)) continue;
    for (const rule of manifest.retiredSymbols || []) {
      if (!file.startsWith(rule.prefix)) continue;
      for (const token of ts) if (rule.names.includes(token.value)) add(file,'retired-symbol',token.value);
    }
    for (const contract of manifest.reservedMembers || []) {
      if (contract.writers.includes(file)) continue;
      // Covers direct access and literal get/set/index access. This is a reserved
      // member namespace, not a claim of whole-program dynamic type inference.
      for (const token of ts) if (token.value.startsWith(contract.prefix)) add(file, 'private-storage', token.value);
    }
    const module = owner(file);
    if (!module) add(file, 'unowned-file', file);
    const pure = isPure(file);
    const code = ts.filter(t => !t.string).map(t => t.value).join(' ');
    if (pure) {
      for (const symbol of PURE_FORBIDDEN) {
        if (ts.some(t => !t.string && t.value === symbol)) add(file, 'pure-core', symbol);
      }
      if (/\bextends\s+(Node\w*|Control|Resource|CharacterBody\w*|RigidBody\w*|Sprite\w*|Canvas\w*|AudioStream\w*)\b/.test(code)) add(file, 'pure-core', 'engine-object');
      if (/\bstatic var\b/.test(code)) add(file, 'mutable-static', 'state');
      // Runtime loading cannot hide dependency edges from this graph.
      if (/\bload\s*\(/.test(code)) add(file, 'dynamic-load', 'load');
    }
    for (let i = 0; i < ts.length; i++) {
      if (ts[i].string || ts[i].value !== 'assert' || ts[i + 1]?.value !== '(') continue;
      let depth = 1;
      for (let j = i + 2; j < ts.length && depth; j++) {
        if (!ts[j].string && ts[j].value === '(') depth++;
        if (!ts[j].string && ts[j].value === ')') depth--;
        // Unknown calls are rejected conservatively: name-based lists of mutations
        // can be bypassed simply by renaming a mandatory initialization method.
        const pureAssertionCalls = new Set(['is_empty','is_inside_tree','is_finite','is_nan','is_inf','is_equal_approx','is_zero_approx','is_instance_valid','typeof','len','size','has']);
        if (!ts[j].string && /^[A-Za-z_][A-Za-z_0-9]*$/.test(ts[j].value) && ts[j + 1]?.value === '(' && !pureAssertionCalls.has(ts[j].value)) add(file, 'assert-side-effect', ts[j].value);
      }
    }
    for (const dependency of dependencies) {
      const other = owner(dependency);
      if (pure && /^(apps|adapters)\//.test(dependency)) add(file, 'dependency-direction', dependency);
      if (module && other && module.name !== other.name) {
        if (!module.allowed.includes(other.name)) add(file, 'module-dependency', dependency);
        else if (!other.public.some(p => covers(dependency, p))) add(file, 'private-api', dependency);
      }
    }
  }
  // Transitive engine access must not be concealed in another core helper.
  for (const [file] of graph) {
    if (!isPure(file) || test(file)) continue;
    const seen = new Set([file]), stack = [...graph.get(file)];
    while (stack.length) {
      const next = stack.pop(); if (seen.has(next)) continue; seen.add(next);
      if (/^(apps|adapters)\//.test(next)) add(file, 'transitive-direction', next);
      if (impure.has(next)) add(file, 'transitive-impurity', next);
      stack.push(...(graph.get(next) || []));
    }
  }
  const visiting = new Set(), done = new Set();
  function visit(file, route) {
    if (visiting.has(file)) { add(file, 'dependency-cycle', [...route.slice(route.indexOf(file)), file].join(' -> ')); return; }
    if (done.has(file) || test(file)) return;
    visiting.add(file);
    for (const next of graph.get(file) || []) visit(next, [...route, file]);
    visiting.delete(file); done.add(file);
  }
  for (const file of graph.keys()) visit(file, []);
  const moduleGraph = new Map(manifest.modules.map(m => [m.name, new Set()]));
  for (const [file, dependencies] of graph) {
    if (test(file)) continue;
    const module = owner(file); if (!module) continue;
    for (const dependency of dependencies) {
      const other = owner(dependency);
      if (other && other.name !== module.name) moduleGraph.get(module.name).add(other.name);
    }
  }
  const activeModules = new Set(), doneModules = new Set();
  function visitModule(name, route) {
    if (activeModules.has(name)) { add(manifest.modules.find(m => m.name === name).prefix, 'module-cycle', [...route.slice(route.indexOf(name)), name].join(' -> ')); return; }
    if (doneModules.has(name)) return;
    activeModules.add(name);
    for (const next of moduleGraph.get(name)) visitModule(next, [...route,name]);
    activeModules.delete(name); doneModules.add(name);
  }
  for (const name of moduleGraph.keys()) visitModule(name, []);
  return [...new Map(issues.map(i => [i.key, i])).values()];
}

function structureIssues(directories, manifest) {
  const errors = [];
  for (const required of manifest.requiredDirectories || []) {
    if (!directories.has(required)) errors.push(`Missing required directory: ${required}`);
  }
  for (const dir of directories) {
    if (!dir.includes('/') && !dir.startsWith('.') && manifest.allowedRoots && !manifest.allowedRoots.includes(dir)) errors.push(`Unknown root directory: ${dir}`);
  }
  return errors;
}

function check() {
  const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, MANIFEST), 'utf8'));
  const malformed = manifestIssues(manifest);
  if (malformed.length) throw new Error(malformed.join('\n'));
  const files = collect(ROOT);
  const directories = new Set(fs.readdirSync(ROOT, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name));
  for (const dir of manifest.requiredDirectories) if (fs.existsSync(path.join(ROOT, dir))) directories.add(dir);
  const issues = analyze(files, manifest);
  const exceptions = new Map(manifest.exceptions.map(e => [e.key, e]));
  for (const e of exceptions.values()) if (!e.reason || !Number.isInteger(e.removeByStage)) throw new Error(`Invalid exception: ${e.key}`);
  const active = new Set(issues.map(i => i.key));
  const errors = [...structureIssues(directories, manifest), ...issues.filter(i => !exceptions.has(i.key)).map(i => i.key)];
  for (const key of exceptions.keys()) if (!active.has(key)) errors.push(`Remove resolved exception: ${key}`);
  const inventory = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/architecture/file-inventory.json'), 'utf8'));
  for (const file of inventory.files) if (!fs.existsSync(path.join(ROOT, file.destination))) errors.push(`Lost migration file: ${file.source} -> ${file.destination}`);
  const sourcePaths = [...new Set([...files.keys(),...inventory.files.map(f=>f.destination)])];
  const ignored = cp.spawnSync('git',['check-ignore','--no-index','-z','--stdin'],{cwd:ROOT,encoding:'utf8',input:sourcePaths.join('\0')+'\0'});
  if (ignored.status !== 0 && ignored.status !== 1) errors.push(`Cannot verify source tracking: ${ignored.stderr}`);
  else errors.push(...ignoredSourceIssues(ignored.stdout.split('\0')));
  const requirements = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/architecture/requirements.json'), 'utf8')).requirements;
  const requirementIds = new Set();
  for (const requirement of requirements) {
    if (requirementIds.has(requirement.id) || !/^[A-Z]+(?:-[A-Z0-9]+)+$/.test(requirement.id)) errors.push(`Invalid/duplicate requirement: ${requirement.id}`);
    requirementIds.add(requirement.id);
    if (!['pending','implemented'].includes(requirement.status) || !Number.isInteger(requirement.stage) || requirement.stage < 0 || requirement.stage > 7) errors.push(`Invalid requirement status/stage: ${requirement.id}`);
    if (requirement.status === 'implemented' && !requirement.checks.length) errors.push(`Requirement lacks proof: ${requirement.id}`);
    if (requirement.status === 'pending' && !requirement.remaining) errors.push(`Requirement lacks remaining work: ${requirement.id}`);
    for (const check of requirement.checks) if (!fs.existsSync(path.join(ROOT, check))) errors.push(`Missing requirement check: ${requirement.id} -> ${check}`);
    if (process.argv.includes('--acceptance') && requirement.status !== 'implemented') errors.push(`Unfinished requirement: ${requirement.id}: ${requirement.remaining}`);
  }
  const baseArg = process.argv.find(a => a.startsWith('--base='));
  {
    const base = baseArg?.slice(7) || 'HEAD';
    if (!/^(?:HEAD|[a-f0-9]{7,40})$/i.test(base)) throw new Error('Architecture base must be HEAD or a commit SHA');
    const previous = cp.spawnSync('git', ['show', `${base}:godot/${MANIFEST}`], { encoding: 'utf8', cwd: ROOT });
    if (previous.status === 0) {
      const prior = new Set(JSON.parse(previous.stdout).exceptions.map(e => e.key));
      for (const key of exceptions.keys()) if (!prior.has(key)) errors.push(`Exception added against ${base}: ${key}`);
      const blueprintPath = 'docs/architecture/BLUEPRINT.md';
      const blueprint = cp.spawnSync('git', ['show', `${base}:godot/${blueprintPath}`], {encoding:'utf8', cwd:ROOT});
      const contractChanged = JSON.stringify(JSON.parse(previous.stdout)) !== JSON.stringify(manifest)
        || (blueprint.status === 0 && blueprint.stdout.replaceAll('\r\n','\n') !== fs.readFileSync(path.join(ROOT,blueprintPath),'utf8').replaceAll('\r\n','\n'));
      const changed = cp.execFileSync('git', ['diff','--name-only',base,'--','godot'], {cwd:path.dirname(ROOT),encoding:'utf8'}).trim().split('\n');
      const added = cp.execFileSync('git', ['ls-files','--others','--exclude-standard','--','godot'], {cwd:path.dirname(ROOT),encoding:'utf8'}).trim().split('\n');
      errors.push(...contractChangeIssues([...changed,...added].map(p=>p.replace(/^godot\//,'')),contractChanged));
    } else if (manifest.exceptions.length) errors.push(`Cannot verify exceptions against ${base}`);
  }
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(`Architecture passed: ${files.size} source/resources, ${exceptions.size} explicit migration exceptions`);
}
if (require.main === module) check();
module.exports = { tokens, collect, analyze, structureIssues, manifestIssues, contractChangeIssues, ignoredSourceIssues, covers, check };
