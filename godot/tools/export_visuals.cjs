/* Rebuild original Canvas art for native Godot. No browser or JS runtime ships with the game.
 * npm install --no-save @napi-rs/canvas; node godot/tools/export_visuals.cjs
 * NODE_PATH can point to a separate authoring-only installation. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createCanvas } = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'godot/ui/assets');
fs.mkdirSync(out, { recursive: true });
const context = vm.createContext({ document: { createElement: () => createCanvas(1, 1), addEventListener() {} }, console });
const source = ['01_core.js', '01b_gear.js', '01c_perks.js', '02_art.js', '05b_worldart.js', '06_ui.js', '06b_inventory.js'].map(n => fs.readFileSync(path.join(root, 'src', n), 'utf8')).join('\n');
context.sCult = s => s.cult || s.fac;
vm.runInContext(source + '\nglobalThis.art = { TROOPS, FACTIONS, EQ, ICONS, PERKS, perkParts, GOOD_IC, buildSprite, hashStr, palOf, crestCanvas, settleSprite, caravanSprite, treeSprite, bushSprite, iconKey, drawTorso, drawHead, drawHelm, drawShield, drawWeapon, drawBase, drawHorse, drawStump, quiver, makeVariant, mulberry };', context);
const a = context.art;
// Godot's SVG rasterizer does not accept CSS four-digit hex alpha attributes.
function svgShapes(shapes) {
  return shapes.replace(/(fill|stroke)="#([\da-f])([\da-f])([\da-f])([\da-f])"/gi,
    (_, property, r, g, b, alpha) => `${property}="#${r}${r}${g}${g}${b}${b}" ${property}-opacity="${parseInt(alpha,16)/15}"`);
}
function exportIcons() {
  for (const [id, shapes] of Object.entries(a.ICONS)) {
    for (const [prefix, color] of [['icon_', '#d1a84c'], ['item_', '#e2d6b4'], ['white_', '#ffffff']]) {
      fs.writeFileSync(path.join(out, prefix + id + '.svg'), `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="${color}" color="${color}">${svgShapes(shapes).replaceAll('currentColor',color)}</svg>`);
    }
  }
}
if (process.argv.includes('--icons-only')) { exportIcons(); process.exit(0); }
const paintGround = vm.runInContext('paintGround', context);
let contactShadowTexture;
const shadowCapture = createCanvas(1, 1).getContext('2d');
shadowCapture.drawImage = image => { contactShadowTexture = image; };
vm.runInContext('contactShadow', context)(shadowCapture, 0, 0, 1, 1);
fs.writeFileSync(path.join(out, 'contact_shadow.png'), contactShadowTexture.toBuffer('image/png'));
// Fixed-size cells keep lookups independent of troop/faction ordering.
const cell = 256, columns = 16;
const entries = [];
for (const [id, troop] of Object.entries(a.TROOPS)) {
  const fac = troop.fac;
  for (const palette of new Set([fac, 'player'])) {
    const sp = a.buildSprite(troop.look, a.palOf(palette), a.hashStr(id));
    entries.push({ key: id + '|' + palette, sp, look: troop.look });
  }
}
const manifest = { troops: {}, crests: {}, icons: {}, items: {}, components: {}, settlements: {}, perks: {} };
manifest.palettes = Object.fromEntries(Object.entries(a.FACTIONS).map(([id, f]) => [id, { c1: f.c1, c2: f.c2, emblem: f.emblem }]));
let troopX = 0, troopY = 0, troopRowHeight = 0;
const troopWidth = 2048;
for (const entry of entries) {
  if (troopX + entry.sp.w > troopWidth) { troopX = 0; troopY += troopRowHeight; troopRowHeight = 0; }
  entry.x = troopX; entry.y = troopY;
  troopX += entry.sp.w; troopRowHeight = Math.max(troopRowHeight, entry.sp.h);
}
const troopHeight = troopY + troopRowHeight;
// Separate sheets preserve the original weapon pivot and decapitation layers.
for (let variant = 0; variant < 4; variant++) {
  const variantEntries = variant === 0 ? entries : entries.map(entry => ({ ...entry, sp: a.buildSprite(entry.look, a.palOf(entry.key.split('|')[1]), a.hashStr(entry.key.split('|')[0]) + variant * 977) }));
for (const part of ['body', 'wpn', 'portrait', 'headless', 'head', 'flash', 'corpse', 'corpse_headless']) {
  const sheet = createCanvas(troopWidth, troopHeight), g = sheet.getContext('2d');
  variantEntries.forEach(({ key, sp, look, x, y }) => {
    const image = part === 'portrait' ? sp.cv : part === 'headless' ? sp.mk(false, { part: 'body', nohead: true }) : part === 'head' ? sp.mk(false, { only: 'head' }) : part === 'corpse' ? sp.mk(false) : part === 'corpse_headless' ? sp.mk(false, { nohead: true }) : sp[part];
    g.drawImage(image, x, y);
    manifest.troops[key] = { rect: [x, y, sp.w, sp.h], anchor: [sp.ax / 2, sp.ay / 2], pivot: sp.piv.map(v => v / 2), look };
  });
  fs.writeFileSync(path.join(out, part + (variant ? '_v' + variant : '') + '.png'), sheet.toBuffer('image/png'));
}
}
for (const [id] of Object.entries(a.FACTIONS)) {
  fs.writeFileSync(path.join(out, 'crest_' + id + '.png'), a.crestCanvas(id, 96).toBuffer('image/png'));
  manifest.crests[id] = 'crest_' + id + '.png';
}
exportIcons();
for (const [id] of Object.entries(a.ICONS)) {
  const name = 'icon_' + id + '.svg';
  manifest.icons[id] = name;
}
for (const [id, item] of Object.entries(a.EQ)) manifest.items[id] = a.iconKey(item);
for (const [id, icon] of Object.entries(a.GOOD_IC)) manifest.items[id] = icon;
for (const perk of a.PERKS) manifest.perks[perk.id] = a.perkParts(perk).map(p => p.t + ' ' + p.v.join(' / ') + p.u).join(', ') + '.';
// Full native equipment composition: any purchased head/body/shield/weapon/horse can be combined.
// Component positions use the same 76x88 coordinate system as drawBust, before its canvas offset.
const components = [];
const looks = Object.values(a.TROOPS).map(t => t.look);
const gearLooks = slot => Object.values(a.EQ).filter(it => it.slot === slot).map(it => it.look);
const values = (field, slot, extra = []) => [...new Set([...looks.map(l => l[field]), ...gearLooks(slot), ...extra].filter(Boolean))];
const addComponent = (key, paint, width = 152, height = 176) => {
  const cv = createCanvas(width, height), g = cv.getContext('2d');
  g.scale(2, 2); g.lineJoin = 'round'; g.lineCap = 'round';
  paint(g); components.push({ key, cv });
};
for (const fac of Object.keys(a.FACTIONS)) {
  const pal = a.palOf(fac), v = a.makeVariant({ beard: 1 }, 7);
  for (const armor of values('armor', 'body', ['tunic'])) addComponent(`torso|${fac}|${armor}`, g => a.drawTorso(g, { armor }, pal, a.mulberry(7)));
  for (const helm of values('helm', 'head', ['none'])) {
    for (const undead of ['', 'zombie', 'skel']) {
      const look = { helm, beard: 1, undead: undead || undefined }, variant = a.makeVariant(look, 7);
      addComponent(`head|${fac}|${helm}|${undead}`, g => { a.drawHead(g, look, variant); a.drawHelm(g, look, variant, pal, a.mulberry(7)); });
    }
  }
  for (const shield of values('shield', 'shield')) addComponent(`shield|${fac}|${shield}`, g => a.drawShield(g, { shield }, pal, a.mulberry(7)));
  for (const weapon of values('weapon', 'melee', gearLooks('ranged'))) addComponent(`weapon|${fac}|${weapon}`, g => a.drawWeapon(g, { weapon }, pal, v));
  addComponent(`base|${fac}`, g => a.drawBase(g, 36, 72, 24, 8.5, pal));
  for (const horse of values('horse', 'horse')) for (const base of [true, false]) addComponent(`${base ? 'horse' : 'horse_corpse'}|${fac}|${horse}`, g => {
    if (base) a.drawBase(g, 54, 104, 40, 10.5, pal); g.save(); g.translate(2, 14); a.drawHorse(g, horse, pal); g.restore();
    g.fillStyle = horse === 'barded' ? pal.c2 : '#3a2a1a'; g.beginPath(); g.moveTo(18, 72); g.quadraticCurveTo(40, 64, 62, 72); g.lineTo(59, 82); g.quadraticCurveTo(40, 87, 21, 82); g.closePath(); g.fill(); g.strokeStyle = '#1b130c'; g.lineWidth = 1.2; g.stroke();
  }, 240, 244);
}
addComponent('quiver', g => a.quiver(g));
addComponent('stump', g => a.drawStump(g, a.makeVariant({ beard: 1 }, 7)));
// Shelf packing retains original 2x resolution without exceeding 4096px texture limits.
let page = 0, x = 0, y = 0, rowHeight = 0, pageEntries = [];
const flush = () => {
  const sheet = createCanvas(4096, y + rowHeight), g = sheet.getContext('2d');
  for (const entry of pageEntries) g.drawImage(entry.cv, entry.x, entry.y);
  fs.writeFileSync(path.join(out, `components_${page}.png`), sheet.toBuffer('image/png'));
  page++; pageEntries = []; x = y = rowHeight = 0;
};
for (const { key, cv } of components) {
  if (x + cv.width > 4096) { x = 0; y += rowHeight; rowHeight = 0; }
  if (y + cv.height > 4096) flush();
  manifest.components[key] = { page, rect: [x, y, cv.width, cv.height] };
  pageEntries.push({ cv, x, y }); x += cv.width; rowHeight = Math.max(rowHeight, cv.height);
}
flush();
const settlements = [];
let sid = 1;
for (const cult of ['nord', 'emp', 'khan', 'kin', 'dom', 'pact', 'emi']) for (const fac of Object.keys(a.FACTIONS)) for (const kind of ['town', 'castle', 'village', 'camp']) {
  const key = `${kind}|${cult}|${fac}`, sp = a.settleSprite({ id: sid++, kind, cult, fac }); settlements.push({ key, sp });
}
const settleSheet = createCanvas(columns * 170, Math.ceil(settlements.length / columns) * 150), sg = settleSheet.getContext('2d');
settlements.forEach(({ key, sp }, i) => { const x = i % columns * 170, y = Math.floor(i / columns) * 150; sg.drawImage(sp.cv, x, y); manifest.settlements[key] = [x, y, 170, 150]; });
fs.writeFileSync(path.join(out, 'settlements.png'), settleSheet.toBuffer('image/png'));
fs.writeFileSync(path.join(out, 'caravan.png'), a.caravanSprite().cv.toBuffer('image/png'));
for (const biome of ['grass', 'snow', 'steppe', 'arid']) for (let variant = 0; variant < 3; variant++) {
  fs.writeFileSync(path.join(out, `tree_${biome}_${variant}.png`), a.treeSprite(biome, 4018 + variant).toBuffer('image/png'));
  if (variant < 2) fs.writeFileSync(path.join(out, `bush_${biome}_${variant}.png`), a.bushSprite(biome, 4021 + variant).toBuffer('image/png'));
}
const groundOut = path.join(root, 'godot/battle/presentation/terrain/assets');
fs.mkdirSync(groundOut, { recursive: true });
for (const biome of process.argv.includes('--skip-ground') ? [] : ['grass', 'snow', 'steppe', 'arid']) {
  fs.writeFileSync(path.join(groundOut, `ground_${biome}.png`), paintGround(2600, 1700, biome, 4017).toBuffer('image/png'));
}
fs.writeFileSync(path.join(out, 'visuals.json'), JSON.stringify(manifest));
fs.writeFileSync(path.join(out, 'visual_manifest.gd'), 'extends RefCounted\nconst DATA = ' + JSON.stringify(manifest) + '\n');
// CSS plank/button gradients with their nested ink and wood borders, exported as nine patches.
for (const [name, colors, inner, border] of [
  ['plank', ['#4a3522', '#33251a', '#241a11'], '#6a4d30', 3],
  ['button', ['#5b4128', '#3a2a1a', '#2a1d12'], '#7c5c38', 2],
  ['primary', ['#b78a32', '#8b6420', '#5f4313'], '#e0b85c', 2],
  ['danger', ['#8b2a1d', '#702217', '#5e1a11'], '#c8523f', 2],
  ['parchment', ['#d8c9a2', '#c5b58d', '#b9a97f'], '#8a7648', 3]
]) {
  const cv = createCanvas(96, 96), g = cv.getContext('2d');
  g.fillStyle = '#150f09'; g.beginPath(); g.roundRect(0, 0, 96, 96, 3); g.fill();
  g.fillStyle = inner; g.fillRect(border, border, 96 - border * 2, 96 - border * 2);
  const gradient = g.createLinearGradient(0, 0, 0, 96);
  colors.forEach((c, i) => gradient.addColorStop(i / 2, c));
  g.fillStyle = gradient; g.fillRect(border + 1, border + 1, 94 - border * 2, 94 - border * 2);
  fs.writeFileSync(path.join(out, name + '.png'), cv.toBuffer('image/png'));
}
console.log(`Exported ${entries.length * 4} original troop variants, ${Object.keys(a.FACTIONS).length} crests, ${Object.keys(a.ICONS).length} icons in three palettes`);
