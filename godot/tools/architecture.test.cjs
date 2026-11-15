const assert = require('node:assert/strict');
const { analyze, tokens, structureIssues } = require('./architecture.cjs');
const manifest = {modules:[
  {name:'a',prefix:'core/a/',allowed:['b'],public:['core/a/api/']},
  {name:'b',prefix:'core/b/',allowed:[],public:['core/b/api/']},
  {name:'view',prefix:'apps/',allowed:['a'],public:['apps/']},
  {name:'io',prefix:'adapters/',allowed:['a'],public:['adapters/']}
]};
function check(sources, rule) {
  const issues = analyze(new Map(Object.entries(sources)), manifest);
  assert(issues.some(i=>i.rule===rule), `Checker missed ${rule}: ${JSON.stringify(issues)}`);
}
check({'core/a/x.gd':`const B = preload('res://core/b/private.gd')`, 'core/b/private.gd':'extends RefCounted'},'private-api');
check({'core/a/x.gd':`const B = preload('res://core/a/helper.gd')`, 'core/a/helper.gd':`const IO = preload('res://adapters/io.gd')`, 'adapters/io.gd':'extends RefCounted'},'transitive-direction');
check({'core/a/x.gd':`const B = preload('res://core/a/helper.gd')`, 'core/a/helper.gd':`const IO = preload('res://legacy/io.gd')`, 'legacy/io.gd':'extends RefCounted\nvar file = FileAccess.open("data", 1)'},'transitive-impurity');
check({'core/a/x.gd':'var object = Resource.new()'},'pure-core');
check({'apps/x.tscn':'[ext_resource path="res://core/b/private.gd"]', 'core/b/private.gd':'extends RefCounted'},'module-dependency');
check({'core/a/x.gd':`const B = preload('uid://abcd')`, 'core/b/private.gd':'extends RefCounted', 'core/b/private.gd.uid':'uid://abcd'},'private-api');
check({'core/a/x.gd':'extends Sprite2D'},'pure-core');
check({'core/a/x.gd':'static var world = {}'},'mutable-static');
check({'apps/x.gd':'assert(catalog.load_data())'},'assert-side-effect');
check({'apps/x.gd':'assert(service.initialize_required_content())'},'assert-side-effect');
check({'core/a/x.gd':'var actor = Node2D.new()'},'pure-core');
check({'core/a/x.gd':'extends Hidden', 'adapters/h.gd':'class_name Hidden\nextends RefCounted'},'dependency-direction');
check({'core/a/x.gd':`const B=preload('res://core/a/b.gd')`, 'core/a/b.gd':`const A=preload('res://core/a/x.gd')`},'dependency-cycle');
check({'core/a/x.gd':`const B=preload('uid://scene')`, 'apps/x.tscn':'[gd_scene format=3 uid="uid://scene"]'},'dependency-direction');
check({'core/a/api/x.gd':`const B=preload('res://core/b/api/y.gd')`, 'core/b/api/y.gd':`const A=preload('res://core/a/api/z.gd')`, 'core/a/api/z.gd':'extends RefCounted'},'module-cycle');
assert(analyze(new Map([['old/x.gd','extends RefCounted']]),{...manifest,forbiddenPaths:['old/']}).some(i=>i.rule==='retired-path'));
assert(structureIssues(new Set(['core']), {requiredDirectories:['core','runtime'],allowedRoots:['core','runtime']}).some(e=>e.includes('Missing required')));
assert(structureIssues(new Set(['core','rogue']), {requiredDirectories:['core'],allowedRoots:['core']}).some(e=>e.includes('Unknown root')));
assert.equal(tokens('# FileAccess\nvar x = "FileAccess"').filter(t=>!t.string&&t.value==='FileAccess').length,0);
assert.equal(analyze(new Map([['core/a/api/x.gd','extends RefCounted\n# Input.get_tree()']]),manifest).length,0);
for (const source of ['var p = frame._render_positions', 'frame.get("_render_positions")[0] = Vector2.ZERO']) {
  assert(analyze(new Map([['apps/x.gd',source]]), {...manifest,reservedMembers:[{prefix:'_render_',writers:['core/a/api/writer.gd']}]}).some(i=>i.rule==='private-storage'));
}
console.log('Architecture checker negative tests passed');
