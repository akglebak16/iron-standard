// One-time bridge while the browser prototype is the reference for troop data.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../../..');
const source = fs.readFileSync(path.join(root, 'src/01_core.js'), 'utf8');
const end = source.indexOf('const GEAR =');
if (end < 0) throw new Error('Troop catalog boundary not found');
const troops = vm.runInNewContext(source.slice(0, end) + '\nTROOPS', {});
// Compatibility mapping for startBattle, battleUpdate, kill and undeadMul in 03_battle.js.
// Serialize gameplay traits explicitly so runtime rules never inspect content IDs or artwork.
for (const troop of Object.values(troops)) {
  const traits = {};
  if (troop.fac === 'undead') {
    traits.morale_base = 999;
    traits.morale_immune = true;
    traits.leader_bond = 'animated_dead';
    traits.leader_loss_chance = 0.35;
  }
  if (troop.look?.undead === 'skel') {
    traits.projectile_damage_multiplier = 0.6;
    traits.blunt_melee_damage_multiplier = 1.4;
  } else if (troop.look?.undead === 'zombie') {
    traits.blunt_melee_damage_multiplier = 1.15;
  }
  if (Object.keys(traits).length > 0) troop.battle_traits = traits;
}
const expected = JSON.stringify(troops, null, 2) + '\n';
const output = path.join(root, 'godot/troops/data/troops.json');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== expected) throw new Error('Godot troop catalog differs from browser source');
  console.log(`Catalog matches: ${Object.keys(troops).length} troop types`);
} else {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, expected);
  console.log(`Exported ${Object.keys(troops).length} troop types`);
}
