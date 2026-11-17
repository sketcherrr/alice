(() => {
  'use strict';
  const personas = {
    gentle: {label: '温柔，但有主见', reply: '那就歇一会儿。不过晚饭得吃，我们先把外卖选了？'},
    playful: {label: '聪明，略带俏皮', reply: '收到，今日切换为省电模式。躺平搭子已上线——零食分我一口。'},
    quiet: {label: '慢热，细腻而克制', reply: '……嗯。那我把声音放轻一点。茶在旁边，想说话了再叫我。'},
  };
  document.querySelectorAll('[data-persona]').forEach(button => {
    button.addEventListener('click', () => {
      const persona = personas[button.dataset.persona];
      document.querySelectorAll('[data-persona]').forEach(option => {
        const active = option === button;
        option.classList.toggle('active', active);
        option.setAttribute('aria-pressed', String(active));
      });
      document.querySelector('#persona-tag').textContent = persona.label;
      document.querySelector('#persona-reply').textContent = persona.reply;
    });
  });

  const canvas = document.querySelector('#pet-canvas');
  const ctx = canvas.getContext('2d');
  const fallback = document.querySelector('#pet-fallback');
  const bubble = document.querySelector('#pet-bubble');
  const caption = document.querySelector('#pet-caption');
  const toggle = document.querySelector('#motion-toggle');
  const character = document.querySelector('#pet-character');
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const motions = {
    idle: {sheet: 'calm', row: 0, timing: [2800, 100, 130, 180]},
    greeting: {sheet: 'social', row: 0, timing: [320, 240, 240, 320]},
    happy: {sheet: 'social', row: 1, timing: [350, 300, 350, 450]},
    tea: {sheet: 'activities', row: 1, timing: [900, 650, 1600, 850]},
    sleeping: {sheet: 'activities', row: 2, timing: [1100, 1100, 1100, 1100]},
  };
  const lines = {
    happy: ['摸到啦。今天的快乐，+1。', '再摸一下也不是不行。', '好啦好啦，鲸鱼要被你摸秃了。'],
    tea: ['碰个杯。今天先不聊 KPI。', '有点烫，慢慢喝。我不赶时间。'],
    sleeping: ['先充会儿电，梦里也可以摸鱼。'],
  };
  const labels = {idle: 'Alice · 陪你待一会儿', greeting: 'Alice · 欢迎来小岛', happy: 'Alice · 今日份摸摸已收到', tea: 'Alice · 喝茶时间，暂停内卷', sleeping: 'Alice · 正在省电模式'};
  const sheets = {};
  const lineCounts = {happy: 0, tea: 0, sleeping: 0};
  let motion = 'idle', started = performance.now(), until = 0, timer = null;
  let paused = reduceMotion.matches, visible = true, lastPaint = '', ready = false;

  function syncToggle() {
    toggle.textContent = paused ? '▷' : 'Ⅱ';
    toggle.setAttribute('aria-pressed', String(paused));
    toggle.setAttribute('aria-label', paused ? '播放角色动画' : '暂停角色动画');
  }
  function setMotion(next, text, duration = 0) {
    motion = next;
    started = performance.now();
    until = duration ? started + duration : 0;
    if (text) bubble.textContent = text;
    caption.textContent = labels[motion];
    document.querySelectorAll('[data-action]').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.action === motion));
      if (button.dataset.action === 'sleeping') button.innerHTML = motion === 'sleeping' ? '<span aria-hidden="true">☀</span> 醒醒啦' : '<span aria-hidden="true">☾</span> 睡会儿';
    });
    character.setAttribute('aria-label', motion === 'sleeping' ? '叫醒 Alice' : '摸摸 Alice');
    lastPaint = '';
    update();
  }
  function interact(action) {
    if (motion === 'sleeping' && action === 'sleeping') {
      setMotion('greeting', '唔……早呀。刚刚梦到一整片珍珠海。', 3400);
      return;
    }
    const options = lines[action];
    const text = options[lineCounts[action]++ % options.length];
    setMotion(action, text, action === 'sleeping' ? 0 : action === 'tea' ? 8000 : 4200);
  }
  function update() {
    clearTimeout(timer);
    if (!ready || !ctx) return;
    const now = performance.now();
    if (until && now >= until) {
      motion = 'idle'; until = 0; started = now;
      caption.textContent = labels.idle;
      document.querySelectorAll('[data-action]').forEach(button => button.setAttribute('aria-pressed', 'false'));
    }
    const spec = motions[motion];
    const img = sheets[spec.sheet];
    let elapsed = paused ? 0 : (now - started) % spec.timing.reduce((a, b) => a + b, 0);
    let frame = 0;
    while (frame < 3 && elapsed >= spec.timing[frame]) elapsed -= spec.timing[frame++];
    const signature = `${motion}-${frame}`;
    if (signature !== lastPaint) {
      const rows = spec.sheet === 'activities' ? 3 : 2;
      const w = img.naturalWidth / 4, h = img.naturalHeight / rows;
      const side = motion === 'sleeping' ? canvas.width * .82 : canvas.width;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, frame * w, spec.row * h, w, h, (canvas.width - side) / 2, canvas.height - side, side, side);
      lastPaint = signature;
    }
    if (visible && !document.hidden && !paused) timer = setTimeout(update, Math.max(30, spec.timing[frame] - elapsed));
    else if (visible && !document.hidden && until) timer = setTimeout(update, Math.max(30, until - now));
  }
  document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => interact(button.dataset.action)));
  character.addEventListener('click', () => interact(motion === 'sleeping' ? 'sleeping' : 'happy'));
  toggle.addEventListener('click', () => {paused = !paused; syncToggle(); lastPaint = ''; update();});
  reduceMotion.addEventListener('change', event => {paused = event.matches; syncToggle(); lastPaint = ''; update();});
  document.addEventListener('visibilitychange', update);
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(entries => {visible = entries[0].isIntersecting; update();}, {rootMargin: '40px'}).observe(canvas);
  }
  syncToggle();
  Promise.all(['calm', 'social', 'activities'].map(name => new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {sheets[name] = img; resolve();};
    img.onerror = reject;
    img.src = `./assets/${name}.png`;
  }))).then(() => {
    if (!ctx) return;
    ready = true;
    canvas.hidden = false;
    fallback.hidden = true;
    update();
  }).catch(() => {
    // Keep the original character illustration usable if an atlas cannot load.
    caption.textContent = 'Alice · 动画暂时没加载好，摸摸照常营业';
    toggle.disabled = true;
  });
})();
