/* Site-standard Shop purchase flow, for every Shop item, not just eggs:
   confirm the spend, then celebrate the unlock.

     const bought = await ShopFlow.purchase({
       item: { name, image, cost },
       gold,                                     // the member's gold before buying
       buy: async () => { ... },                 // performs the purchase; throw an Error to show its message
       celebration: () => ({                     // an object, or a function called after buy()
         message: 'The Curious Egg has been added to your collection.',
         note: 'Find it in the corner of the screen.',   // optional second line
         actions: [{ label: 'View collection', onClick }],
         choice: { question, smallPrint, yesLabel, noLabel, checkboxLabel },   // optional: ask instead of "Nice!"
       }),
     });
     // false if cancelled or failed; otherwise { answer: 'yes' | 'no' | null, checked }

     const value = await ShopFlow.dialog({ title, html, buttons: [{ label, value, primary }], onOpen(card) {} });

   The unlock chime goes through window.Sfx (pets/helpers/sfx.js), if it's loaded. */
(function (root) {
  const STYLE_ID = 'shop-flow-style';
  const CSS = `
  .sf-backdrop{ position:fixed; inset:0; z-index:1000; background:rgba(10,7,3,.72); display:flex; align-items:center; justify-content:center; padding:16px;
    animation:sfFade .18s ease-out; }
  @keyframes sfFade{ from{ opacity:0; } to{ opacity:1; } }
  .sf-card{ position:relative; width:min(380px, 100%); background:#2f2515; border:1px solid rgba(207,154,68,.45); border-radius:6px; padding:22px 20px 18px;
    text-align:center; color:#ece0c8; font:15px/1.5 system-ui, sans-serif; box-shadow:0 10px 40px rgba(0,0,0,.6); animation:sfRise .22s ease-out; }
  @keyframes sfRise{ from{ transform:translateY(10px) scale(.98); opacity:0; } to{ transform:none; opacity:1; } }
  .sf-title{ font-size:18px; font-weight:800; color:#f0dfb4; margin:0 0 4px; }
  .sf-art{ position:relative; width:100%; height:120px; margin:6px 0 12px; display:flex; align-items:center; justify-content:center; }
  .sf-art img{ max-width:100%; max-height:120px; object-fit:contain; border-radius:4px; position:relative; z-index:1; }
  .sf-cost{ display:flex; justify-content:center; gap:18px; font-size:14px; color:#a4926c; margin:8px 0 2px; }
  .sf-cost b{ color:#f0dfb4; }
  .sf-buttons{ display:flex; gap:8px; justify-content:center; margin-top:16px; flex-wrap:wrap; }
  .sf-btn{ font:700 14px system-ui, sans-serif; border-radius:3px; padding:8px 14px; cursor:pointer; border:1px solid rgba(207,154,68,.4); background:transparent; color:#f0dfb4; }
  .sf-btn.primary{ background:#cf9a44; color:#1a1408; border-color:#cf9a44; }
  .sf-btn:disabled{ opacity:.5; cursor:default; }
  .sf-error{ color:#e08a85; font-size:14px; margin-top:10px; }

  /* the unlock */
  .sf-card.unlock{ overflow:hidden; }
  .sf-rays{ position:absolute; left:50%; top:50%; width:320px; height:320px; margin:-160px; border-radius:50%; z-index:0; pointer-events:none;
    background:repeating-conic-gradient(rgba(240,200,110,.28) 0deg 9deg, rgba(240,200,110,0) 9deg 22.5deg);
    -webkit-mask:radial-gradient(circle, #000 20%, transparent 68%); mask:radial-gradient(circle, #000 20%, transparent 68%);
    animation:sfRays 9s linear infinite, sfFade .5s ease-out; }
  @keyframes sfRays{ to{ transform:rotate(360deg); } }
  .sf-card.unlock .sf-art img{ animation:sfReveal .7s cubic-bezier(.3,1.5,.5,1) both; }
  @keyframes sfReveal{ 0%{ transform:scale(.3) rotateY(180deg); opacity:0; filter:brightness(3); } 60%{ opacity:1; } 100%{ transform:scale(1) rotateY(0); filter:brightness(1); } }
  .sf-card.unlock .sf-title{ animation:sfPop .45s ease-out .35s both; }
  .sf-card.unlock .sf-msg, .sf-card.unlock .sf-note, .sf-card.unlock .sf-choice, .sf-card.unlock .sf-buttons{ animation:sfRiseIn .4s ease-out .55s both; }
  @keyframes sfPop{ 0%{ transform:scale(.6); opacity:0; } 70%{ transform:scale(1.08); opacity:1; } 100%{ transform:scale(1); } }
  @keyframes sfRiseIn{ from{ transform:translateY(8px); opacity:0; } to{ transform:none; opacity:1; } }
  .sf-note{ font-size:13px; color:#a4926c; margin-top:4px; }
  .sf-question{ font-weight:700; color:#f0dfb4; margin-top:14px; }
  .sf-small{ font-size:12px; color:#a4926c; font-style:italic; }
  .sf-check{ display:flex; gap:6px; align-items:center; justify-content:center; font-size:13px; color:#ece0c8; margin-top:10px; cursor:pointer; }
  .sf-card select{ background:#261c11; color:#ece0c8; border:1px solid rgba(207,154,68,.4); border-radius:3px; padding:6px 8px; font:inherit; }
  .sf-body{ text-align:left; font-size:14px; }
  .sf-spark{ position:absolute; left:50%; top:50%; width:6px; height:6px; margin:-3px; border-radius:50%; z-index:2; pointer-events:none;
    animation:sfSpark .9s ease-out .15s both; }
  @keyframes sfSpark{ 0%{ opacity:1; transform:translate(0,0) scale(1); } 100%{ opacity:0; transform:translate(var(--tx),var(--ty)) scale(.3); } }

  @media (prefers-reduced-motion: reduce){
    .sf-rays, .sf-card.unlock .sf-art img, .sf-card.unlock .sf-title, .sf-spark{ animation:sfFade .3s ease-out both; }
    .sf-spark{ display:none; }
  }`;

  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  const chime = () => root.Sfx && root.Sfx.play('chime');

  function open(html, className = '') {
    ensureStyle();
    const backdrop = document.createElement('div');
    backdrop.className = 'sf-backdrop';
    backdrop.innerHTML = `<div class="sf-card ${className}" role="dialog" aria-modal="true">${html}</div>`;
    document.body.appendChild(backdrop);
    return backdrop;
  }

  // Resolves true when the member confirms, false on Cancel, Escape or a click outside.
  function confirmSpend({ item, gold, buy }) {
    return new Promise(resolve => {
      const after = gold - item.cost;
      const dlg = open(`
        <p class="sf-title">Spend ${item.cost} gold?</p>
        <div class="sf-art"><img src="${esc(item.image)}" alt=""></div>
        <div><strong>${esc(item.name)}</strong></div>
        <div class="sf-cost"><span>You have <b>${gold}</b></span><span>After <b>${after}</b></span></div>
        <div class="sf-error" hidden></div>
        <div class="sf-buttons">
          <button class="sf-btn" data-sf="cancel">Cancel</button>
          <button class="sf-btn primary" data-sf="ok">Spend ${item.cost} gold</button>
        </div>`);
      const ok = dlg.querySelector('[data-sf=ok]');
      const close = result => { document.removeEventListener('keydown', onKey); dlg.remove(); resolve(result); };
      const onKey = e => { if (e.key === 'Escape') close(false); };
      document.addEventListener('keydown', onKey);
      dlg.addEventListener('click', async e => {
        if (e.target === dlg || e.target.dataset.sf === 'cancel') return close(false);
        if (e.target !== ok) return;
        // Stay open while buying, so a failure can be shown in place.
        ok.disabled = true;
        ok.textContent = 'Buying…';
        try {
          await buy();
          close(true);
        } catch (err) {
          const box = dlg.querySelector('.sf-error');
          box.hidden = false;
          box.textContent = err.message || "Couldn't complete the purchase.";
          ok.disabled = false;
          ok.textContent = `Spend ${item.cost} gold`;
        }
      });
      ok.focus();
    });
  }

  function celebrate({ item, message, note, actions = [], choice }) {
    return new Promise(resolve => {
      const buttons = choice
        ? `<button class="sf-btn" data-sf="no">${esc(choice.noLabel || 'Not now')}</button>
           <button class="sf-btn primary" data-sf="yes">${esc(choice.yesLabel || 'Yes')}</button>`
        : `${actions.map((a, i) => `<button class="sf-btn" data-sf-action="${i}">${esc(a.label)}</button>`).join('')}
           <button class="sf-btn primary" data-sf="close">Nice!</button>`;
      const dlg = open(`
        <div class="sf-rays"></div>
        <div class="sf-art"><img src="${esc(item.image)}" alt=""></div>
        <p class="sf-title">Congratulations!</p>
        <div class="sf-msg">${esc(message)}</div>
        ${note ? `<div class="sf-note">${esc(note)}</div>` : ''}
        ${choice ? `<div class="sf-choice">
          <div class="sf-question">${esc(choice.question)}</div>
          ${choice.smallPrint ? `<div class="sf-small">${esc(choice.smallPrint)}</div>` : ''}
          ${choice.checkboxLabel ? `<label class="sf-check"><input type="checkbox" data-sf="check"> ${esc(choice.checkboxLabel)}</label>` : ''}
        </div>` : ''}
        <div class="sf-buttons">${buttons}</div>`, 'unlock');
      const card = dlg.querySelector('.sf-card');
      const colors = ['#fff3c4', '#f0c86e', '#cf9a44', '#ffffff'];
      for (let i = 0; i < 18; i++) {
        const s = document.createElement('div');
        s.className = 'sf-spark';
        const angle = (i / 18) * Math.PI * 2;
        const dist = 90 + Math.random() * 70;
        s.style.cssText = `--tx:${Math.cos(angle) * dist}px; --ty:${Math.sin(angle) * dist - 30}px; background:${colors[i % 4]}; top:35%;`;
        card.appendChild(s);
      }
      chime();
      const checked = () => !!dlg.querySelector('[data-sf=check]')?.checked;
      const close = answer => { document.removeEventListener('keydown', onKey); dlg.remove(); resolve({ answer, checked: checked() }); };
      // Escape or a click outside never answers a question; it counts as "not now".
      const onKey = e => { if (e.key === 'Escape') close(choice ? 'no' : null); else if (e.key === 'Enter' && !choice) close(null); };
      document.addEventListener('keydown', onKey);
      dlg.addEventListener('click', e => {
        const t = e.target;
        const i = t.dataset.sfAction;
        if (i !== undefined) { close(null); actions[i].onClick(); }
        else if (t.dataset.sf === 'yes') close('yes');
        else if (t.dataset.sf === 'no') close('no');
        else if (t === dlg) close(choice ? 'no' : null);
        else if (t.dataset.sf === 'close') close(null);
      });
      dlg.querySelector('[data-sf=yes], [data-sf=close]').focus();
    });
  }

  async function purchase({ item, gold, buy, celebration }) {
    const bought = await confirmSpend({ item, gold, buy });
    if (!bought) return false;
    // The celebration can depend on what buy() did, so it may be a function called afterwards.
    return celebrate({ item, ...(typeof celebration === 'function' ? celebration() : celebration) });
  }

  // A plain dialog. Resolves with the clicked button's value (null on Escape or a click outside).
  function dialog({ title, html, buttons = [{ label: 'OK', value: true, primary: true }], onOpen }) {
    return new Promise(resolve => {
      const dlg = open(`
        <p class="sf-title">${esc(title)}</p>
        <div class="sf-body">${html}</div>
        <div class="sf-buttons">${buttons.map((b, i) => `<button class="sf-btn ${b.primary ? 'primary' : ''}" data-sf-button="${i}">${esc(b.label)}</button>`).join('')}</div>`);
      const close = value => { document.removeEventListener('keydown', onKey); dlg.remove(); resolve(value); };
      const onKey = e => { if (e.key === 'Escape') close(null); };
      document.addEventListener('keydown', onKey);
      dlg.addEventListener('click', e => {
        const i = e.target.dataset.sfButton;
        if (i !== undefined) close(buttons[i].value);
        else if (e.target === dlg) close(null);
      });
      if (onOpen) onOpen(dlg.querySelector('.sf-card'));
      (dlg.querySelector('.sf-btn.primary') || dlg.querySelector('.sf-btn'))?.focus();
    });
  }

  const ShopFlow = { purchase, confirmSpend, celebrate, dialog };
  root.ShopFlow = ShopFlow;
})(window);
