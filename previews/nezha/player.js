/* Runtime atlas player: reads original PNGs without changing their pixels. */
(() => {
  'use strict';
  const art = window.NEZHA_ART;
  const $ = (id) => document.getElementById(id);
  const canvas = $('stage'), ctx = canvas.getContext('2d');
  const images = new Map();
  const actorKeys = ['idle', 'run', 'attack', 'qiankun', 'samadhi', 'fire_field', 'hit', 'defeat'];
  const fxKeys = ['spear_fx', 'ring_fx', 'burn_fx', 'passive_fx', 'samadhi_fx', 'fire_field_fx'];
  const state = {key: 'idle', time: 0, playing: true, speed: 1, background: 'stage', height: 320, effects: true, flip: false, demo: false};
  const demo = [['idle', 2000], ['run', 1700], ['attack', 2200], ['qiankun', 2500], ['samadhi', 3000], ['fire_field', 3000], ['passive_fx', 1800], ['hit', 1200], ['defeat', 2000]];
  const sum = (a) => a.reduce((s, n) => s + n, 0);
  const duration = (key) => sum(art.clips[key].durations_ms);
  const period = (key) => duration(key) + ({attack: 500, qiankun: 500, samadhi: 700, fire_field: 900, hit: 600, defeat: 700, passive_fx: 450}[key] || 0);
  const ease = (t) => t * t * (3 - 2 * t);
  function pose(key, time) {
    const clip = art.clips[key];
    let t = Math.max(0, time);
    if (clip.loop) t %= duration(key);
    for (let i = 0; i < clip.frames.length; i++) {
      if (t < clip.durations_ms[i]) return i;
      t -= clip.durations_ms[i];
    }
    return clip.frames.length - 1;
  }
  function drawClip(key, time, x, y, height, flip = false, alpha = 1, context = ctx) {
    const clip = art.clips[key], sheet = art.sheets[clip.sheet];
    const frame = sheet.frames[clip.frames[pose(key, time)]];
    const [sx, sy, sw, sh] = frame.source, scale = height / sheet.body_height;
    context.save(); context.translate(x, y); context.scale(flip ? -1 : 1, 1); context.globalAlpha = alpha;
    context.drawImage(images.get(sheet.path), sx, sy, sw, sh, -frame.pivot[0] * scale, -frame.pivot[1] * scale, sw * scale, sh * scale);
    context.restore();
  }
  function shortEffect(key, time, x, y, size, flip = false, rotation = 0) {
    if (time >= 0 && time < duration(key)) {
      ctx.save(); ctx.translate(x, y); ctx.scale(flip ? -1 : 1, 1); ctx.rotate(rotation);
      drawClip(key, time, 0, 0, size); ctx.restore();
    }
  }
  function background() {
    if (state.background === 'battle') {
      const im = images.get('assets/battle/fortress_amber.webp');
      const scale = Math.max(1100 / im.width, 770 / im.height);
      ctx.drawImage(im, (1100 - im.width * scale) / 2, -130, im.width * scale, im.height * scale);
      ctx.fillStyle = '#151d2b55'; ctx.fillRect(0, 0, 1100, 650);
    } else if (state.background === 'checker') {
      for (let y = 0; y < 650; y += 24) for (let x = 0; x < 1100; x += 24) {
        ctx.fillStyle = ((x + y) / 24) % 2 ? '#ddd9d0' : '#f4f1e9'; ctx.fillRect(x, y, 24, 24);
      }
    } else {
      const g = ctx.createLinearGradient(0, 0, 0, 650);
      g.addColorStop(0, state.background === 'light' ? '#f6efdf' : '#18232a');
      g.addColorStop(1, state.background === 'light' ? '#d6c9b2' : '#2b2c2d');
      ctx.fillStyle = g; ctx.fillRect(0, 0, 1100, 650);
    }
    const light = ['light', 'checker'].includes(state.background);
    ctx.strokeStyle = light ? '#77674a40' : '#bda67930'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(100, 502); ctx.lineTo(1000, 502); ctx.stroke();
    ctx.fillStyle = light ? '#796644' : '#bca679'; ctx.font = '13px sans-serif';
    ctx.fillText('哪吒 · 第二版 / 无风火轮', 34, 38);
    ctx.textAlign = 'right'; ctx.fillText('人物动作与独立特效', 1066, 38); ctx.textAlign = 'left';
  }
  function drawStage(key, time) {
    background();
    const fx = fxKeys.includes(key), h = state.height, base = 500;
    const direction = state.flip ? -1 : 1;
    const mainX = fx ? 550 : (state.effects && ['attack', 'qiankun', 'samadhi', 'fire_field'].includes(key) ? 390 : 550);
    const actorX = state.flip ? 1100 - mainX : mainX;
    const target = actorX + direction * (h * .85);
    if (fx) {
      if (key === 'passive_fx') {
        drawClip('idle', time, actorX, base, h, state.flip);
        drawClip(key, time, actorX, base + 4, h * .96, state.flip);
      } else if (key === 'burn_fx') drawClip(key, time, 550, base, 260);
      else if (key === 'ring_fx' || key === 'spear_fx') drawClip(key, time, 550, 340, 340, state.flip);
      else drawClip(key, time, 550, base, 520);
    } else {
      const finished = time >= duration(key);
      const actorKey = finished && !['defeat', 'run', 'idle'].includes(key) ? 'idle' : key;
      // The field appears behind the actor; the strike bloom appears in front.
      if (state.effects && key === 'fire_field') shortEffect('fire_field_fx', time - 620, target, base, 470);
      drawClip(actorKey, actorKey === key ? time : time - duration(key), actorX, base, h, state.flip);
      if (state.effects) {
        if (key === 'attack') {
          const ratio = h / art.sheets.attack.body_height;
          for (const event of art.clips.attack.events) {
            shortEffect('spear_fx', (time - event.at_ms) * 1.75,
              actorX + direction * event.socket[0] * ratio,
              base + event.socket[1] * ratio, h * .4, state.flip, event.rotation);
          }
        }
        if (key === 'qiankun' && time >= 360 && time < 860) {
          const u = (time - 360) / 500, travel = Math.sin(Math.PI * u);
          const ringX = actorX + direction * (h * (.42 - .18 * u) + travel * h * .65);
          const ringY = base - h * (.78 - .18 * u) - travel * 35;
          drawClip('ring_fx', time - 360, ringX, ringY, h * .34, state.flip);
        }
        if (key === 'samadhi') shortEffect('samadhi_fx', time - 420, target, base + 4, h * 1.4);
      }
    }
    ctx.fillStyle = ['light', 'checker'].includes(state.background) ? '#4e453b' : '#e2c693';
    ctx.font = '26px Shanhe,serif'; ctx.textAlign = 'center';
    ctx.fillText(art.clips[key].name, 550, 576);
    ctx.font = '13px sans-serif'; ctx.fillStyle = ['light', 'checker'].includes(state.background) ? '#76664e' : '#999b98';
    ctx.fillText(fx ? '独立特效序列' : '角色关键帧 · 脚底锚点对齐', 550, 605); ctx.textAlign = 'left';
  }
  function updateUI() {
    const key = state.key, clip = art.clips[key], at = pose(key, state.time);
    $('clipName').textContent = clip.name;
    $('clipMeta').textContent = `${clip.frames.length} 帧 · ${clip.loop ? '循环动作' : '起手 / 释放 / 收招'}`;
    $('frameLabel').textContent = `${at + 1} / ${clip.frames.length}`;
    $('timeLabel').textContent = (state.time / 1000).toFixed(2) + ' s';
    $('time').max = period(key); $('time').value = state.time;
    $('play').textContent = state.playing ? '暂停' : '播放'; $('play').setAttribute('aria-label', state.playing ? '暂停播放' : '播放动画');
    document.querySelectorAll('[data-clip]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.clip === key)));
    document.querySelectorAll('.frame').forEach((b, i) => b.classList.toggle('current', i === at));
  }
  function thumbnails() {
    const key = state.key, clip = art.clips[key];
    $('description').textContent = clip.description;
    $('frames').replaceChildren();
    let start = 0;
    clip.frames.forEach((_, i) => {
      const stamp = start; start += clip.durations_ms[i];
      const b = document.createElement('button'), c = document.createElement('canvas'), label = document.createElement('span');
      b.className = 'frame'; b.type = 'button'; b.setAttribute('aria-label', `查看第 ${i + 1} 帧`); c.width = 180; c.height = 180;
      const cx = c.getContext('2d'); cx.fillStyle = '#2a2d30'; cx.fillRect(0, 0, 180, 180);
      const sheet = art.sheets[clip.sheet], frame = sheet.frames[clip.frames[i]];
      const [sx, sy, sw, sh] = frame.source;
      // Constant whole-cell framing in thumbnails; no pose-dependent distortion.
      const scale = Math.min(170 / 512, 170 / 512) * (sheet.columns === 4 ? 512 / (sheet.size[0] / 4) : 1);
      cx.drawImage(images.get(sheet.path), sx, sy, sw, sh, 90 - sw * scale / 2, 90 - sh * scale / 2, sw * scale, sh * scale);
      label.textContent = `${String(i + 1).padStart(2, '0')} · ${clip.durations_ms[i]} ms`;
      b.append(c, label); b.addEventListener('click', () => {state.playing = false; state.time = stamp; state.demo = false; drawStage(key, stamp); updateUI();});
      $('frames').append(b);
    });
  }
  function setClip(key, autoplay = true) {
    if (!art.clips[key]) throw new Error('Unknown clip ' + key);
    state.key = key; state.time = 0; state.playing = autoplay; state.demo = false; thumbnails(); drawStage(key, 0); updateUI();
  }
  let last = performance.now();
  function tick(now) {
    const dt = Math.min(now - last, 100); last = now;
    if (!state.demo && state.playing) state.time = (state.time + dt * state.speed) % period(state.key);
    if (!state.demo) {drawStage(state.key, state.time); updateUI();}
    requestAnimationFrame(tick);
  }
  function drawDemo(ms) {
    state.demo = true; let t = ms;
    for (const [key, length] of demo) {
      if (t < length) {drawStage(key, t % period(key)); return key;}
      t -= length;
    }
    drawStage('idle', 0); return 'idle';
  }
  async function init() {
    const paths = new Set([art.portrait, art.battle_master, 'assets/battle/fortress_amber.webp', ...Object.values(art.sheets).map(s => s.path)]);
    await Promise.all([...paths].map(path => new Promise((resolve, reject) => {
      const im = new Image(); im.onload = () => {images.set(path, im); resolve();}; im.onerror = () => reject(new Error('Missing image: ' + path)); im.src = '../../' + path;
    })));
    await document.fonts.ready;
    $('portrait').src = '../../' + art.portrait;
    for (const [key, id] of [['map', 'mapPortrait'], ['battle', 'battlePortrait']]) {
      const c = $(id), cx = c.getContext('2d'); cx.fillStyle = '#49392e'; cx.fillRect(0, 0, c.width, c.height);
      cx.drawImage(images.get(art.portrait), ...art.portrait_regions[key], 0, 0, c.width, c.height);
    }
    for (const [keys, id] of [[actorKeys, 'actorClips'], [fxKeys, 'fxClips']]) for (const key of keys) {
      const b = document.createElement('button'); b.type = 'button'; b.dataset.clip = key; b.textContent = art.clips[key].name; b.addEventListener('click', () => setClip(key)); $(id).append(b);
    }
    $('play').onclick = () => {state.demo = false; state.playing = !state.playing; updateUI();};
    $('replay').onclick = () => setClip(state.key);
    $('time').oninput = () => {state.playing = false; state.demo = false; state.time = +$('time').value; drawStage(state.key, state.time); updateUI();};
    for (const [id, prop] of [['speed', 'speed'], ['scale', 'height']]) $(id).onchange = () => state[prop] = +$(id).value;
    $('background').onchange = () => state.background = $('background').value;
    $('effects').onchange = () => state.effects = $('effects').checked;
    $('flip').onchange = () => state.flip = $('flip').checked;
    document.addEventListener('keydown', e => {if (e.code === 'Space' && !['INPUT', 'SELECT', 'BUTTON'].includes(e.target.tagName)) {e.preventDefault(); $('play').click();}});
    window.NezhaPreview = {art, state, setClip, drawDemo, demoDuration: sum(demo.map(x => x[1])), render: drawStage, period,
      seek(key, ms) {setClip(key, false); state.time = ms; drawStage(key, ms); updateUI();}, ready: true};
    setClip('idle'); requestAnimationFrame(tick);
  }
  init().catch(error => {$('clipName').textContent = '资源加载失败'; $('description').textContent = error.message; $('description').classList.add('error'); console.error(error);});
})();
