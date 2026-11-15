const assert = require('node:assert/strict');
const { analyze, tokens, structureIssues, manifestIssues, contractChangeIssues, ignoredSourceIssues, covers } = require('./architecture.cjs');
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
check({'core/a/x.gd':'var main = Engine.get_main_loop()'},'pure-core');
check({'core/a/x.gd':'var main = ClassDB.instantiate("Node")'},'pure-core');
check({'core/a/x.gd':'const Asset=preload("res://apps/icon.png")','apps/icon.png':''},'dependency-direction');
check({'core/a/x.gd':'const Extension=preload("uid://extension")','adapters/native.gdextension':'[configuration]','adapters/native.gdextension.uid':'uid://extension'},'dependency-direction');
check({'core/a/x.gd':'const Asset=preload("uid://image")','apps/icon.png':'','apps/icon.png.import':'[remap]\nuid="uid://image"'},'dependency-direction');
check({'core/a/x.gd':'const Data=preload("res://core/a/data.json")','core/a/data.json':'{}'},'transitive-impurity');
check({'core/a/x.gd':'const Sound=preload("res://apps/missing.ogg")'},'missing-reference');
check({'core/a/x.gd':'var main = ClassDB.instantiate("HiddenKernel")','adapters/hidden.cpp':'GDCLASS(HiddenKernel, RefCounted)'},'dependency-direction');
check({'apps/x.gd':'var main = ClassDB.instantiate("HiddenKernel")','core/b/private.cpp':'GDCLASS(HiddenKernel, RefCounted)'},'module-dependency');
check({'core/a/native.cpp':'#include <godot_cpp/variant/vector2.hpp>'},'native-purity');
check({'core/a/native.cpp':'#include <fstream>'},'native-purity');
check({'core/a/native.cpp':'static int world = 0;'},'mutable-static');
check({'core/a/native.cpp':'#include "../../b/private.hpp"','core/b/private.hpp':'#include <vector>'},'missing-reference');
check({'core/a/native.cpp':'#include "../b/private.hpp"','core/b/private.hpp':'#include <vector>'},'private-api');
check({'core/a/native.cpp':'#include "../../adapters/hidden.hpp"','adapters/hidden.hpp':'#include <godot_cpp/classes/node.hpp>'},'transitive-impurity');
assert.equal(analyze(new Map([['core/a/native.cpp','#include <vector>\n// godot::Node is forbidden, but this is a comment\nstatic int compute(int x) { return x; }']]),manifest).length,0);
check({'core/a/x.gd':'var t = Time.get_ticks_usec()'},'pure-core');
check({'core/a/x.gd':'OS.execute("helper", [])'},'pure-core');
check({'core/a/x.gd':'static var world = {}'},'mutable-static');
check({'core/a/one.gd.uid':'uid://duplicate','core/a/two.gd.uid':'uid://duplicate'},'duplicate-uid');
check({'core/a/one.gd':'class_name Same','core/a/two.gd':'class_name Same'},'duplicate-class');
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
assert.deepEqual(tokens('# comment\nvar text = """a\nb"""\n# next\nvar end = 1').filter(t=>t.value==='var').map(t=>t.line),[2,5]);
assert.equal(analyze(new Map([['core/a/api/x.gd','extends RefCounted\n# Input.get_tree()']]),manifest).length,0);
for (const source of ['var p = frame._render_positions', 'frame.get("_render_positions")[0] = Vector2.ZERO']) {
  assert(analyze(new Map([['apps/x.gd',source]]), {...manifest,reservedMembers:[{prefix:'_render_',writers:['core/a/api/writer.gd']}]}).some(i=>i.rule==='private-storage'));
}
const owned = {...manifest,modules:manifest.modules.map(m=>({...m,owner:m.name}))};
assert.deepEqual(manifestIssues(owned),[]);
assert(manifestIssues({...owned,modules:[...owned.modules,{name:'nested',owner:'nested',prefix:'core/a/nested/',allowed:[],public:[]}]}).some(e=>e.includes('Overlapping')));
assert(manifestIssues({...owned,modules:[...owned.modules,owned.modules[0]]}).some(e=>e.includes('Duplicate/missing')));
assert(manifestIssues({...owned,modules:owned.modules.map(m=>({...m,allowed:['unknown']}))}).some(e=>e.includes('Invalid allowed')));
assert(manifestIssues({...owned,modules:owned.modules.map(m=>({...m,public:['../internal.gd']}))}).some(e=>e.includes('Public entry')));
assert(manifestIssues(manifest).some(e=>e.includes('Missing module owner')));
assert(covers('core/a/api.gd','core/a/api.gd'));
assert(!covers('core/a/api.gd.internal.gd','core/a/api.gd'));
const exactPublic = {...manifest,modules:manifest.modules.map(m=>m.name==='b'?{...m,public:['core/b/api.gd']}:m)};
assert(analyze(new Map([['core/a/x.gd','const B=preload("res://core/b/api.gd.internal.gd")'],['core/b/api.gd.internal.gd','extends RefCounted']]),exactPublic).some(i=>i.rule==='private-api'));
assert.equal(contractChangeIssues([],false).length,0);
assert.equal(contractChangeIssues([],true).length,2);
assert.equal(contractChangeIssues(['docs/architecture/ADR-008.md'],true).length,1);
assert.equal(contractChangeIssues(['tests/integration/test_contract.gd'],true).length,1);
assert.equal(contractChangeIssues(['docs/architecture/ADR-008.md','tools/architecture.test.cjs'],true).length,0);
assert.deepEqual(ignoredSourceIssues(['']),[]);
assert(ignoredSourceIssues(['core/troops/data/catalog.gd'])[0].includes('ignored by Git'));
for(const source of ['var target_index = 4','unit.set("target_index", 4)']) {
 assert(analyze(new Map([['core/a/x.gd',source]]),{...manifest,retiredSymbols:[{prefix:'core/a/',names:['target_index']}]}).some(i=>i.rule==='retired-symbol'));
}
console.log('Architecture checker negative tests passed');
