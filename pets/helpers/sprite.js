/* Renders one animation from an egg.json / monster.json "animations" entry as an HTML string.
   A single image or GIF is shown as it is. A horizontal sprite strip (frames > 1) is
   played with CSS steps(), so no extra files or libraries are needed. */
(function (root) {
  const STYLE_ID = 'pet-sprite-style';

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      .pet-sprite{ position:relative; overflow:hidden; display:inline-block; }
      .pet-sprite > img{ display:block; height:100%; image-rendering:pixelated; }
      .pet-sprite.strip > img{ width:auto; animation:pet-sprite-play var(--dur) steps(var(--frames)) infinite; }
      .pet-sprite.still > img{ width:100%; object-fit:contain; }
      @keyframes pet-sprite-play{ from{ transform:translateX(0); } to{ transform:translateX(-100%); } }
    `;
    document.head.appendChild(style);
  }

  // anim: { src, frames?, fps?, frame_width?, frame_height? }; baseUrl: the egg or monster folder.
  function petSpriteHtml(anim, baseUrl, sizePx = 96, alt = '') {
    ensureStyle();
    const src = baseUrl.replace(/\/?$/, '/') + anim.src;
    const frames = anim.frames || 1;
    if (frames === 1) {
      return `<span class="pet-sprite still" style="width:${sizePx}px; height:${sizePx}px;"><img src="${src}" alt="${alt}"></span>`;
    }
    const width = Math.round(sizePx * anim.frame_width / anim.frame_height);
    const dur = (frames / (anim.fps || 8)).toFixed(3) + 's';
    return `<span class="pet-sprite strip" style="width:${width}px; height:${sizePx}px; --frames:${frames}; --dur:${dur};"><img src="${src}" alt="${alt}"></span>`;
  }

  root.petSpriteHtml = petSpriteHtml;
})(window);
