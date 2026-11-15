const assert = require('node:assert/strict');
const { analyze, tokens } = require('./architecture.cjs');
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
check({'apps/x.tscn':'[ext_resource path="res://core/b/private.gd"]', 'core/b/private.gd':'extends RefCounted'},'module-dependency');
check({'core/a/x.gd':`const B = preload('uid://abcd')`, 'core/b/private.gd':'extends RefCounted', 'core/b/private.gd.uid':'uid://abcd'},'private-api');
check({'core/a/x.gd':'extends Sprite2D'},'pure-core');
check({'core/a/x.gd':'static var world = {}'},'mutable-static');
check({'apps/x.gd':'assert(catalog.load_data())'},'assert-side-effect');
check({'core/a/x.gd':'extends Hidden', 'adapters/h.gd':'class_name Hidden\nextends RefCounted'},'dependency-direction');
check({'core/a/x.gd':`const B=preload('res://core/a/b.gd')`, 'core/a/b.gd':`const A=preload('res://core/a/x.gd')`},'dependency-cycle');
assert.equal(tokens('# FileAccess\nvar x = "FileAccess"').filter(t=>!t.string&&t.value==='FileAccess').length,0);
assert.equal(analyze(new Map([['core/a/api/x.gd','extends RefCounted\n# Input.get_tree()']]),manifest).length,0);
console.log('Architecture checker negative tests passed');
