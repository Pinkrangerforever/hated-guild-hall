/* ---------------- calendar tab ---------------- */
function rsvpGroupsFor(eventId){
  const groups = { going:[], maybe:[], out:[] };
  state.rsvps.filter(r=>r.event_id===eventId).forEach(r=>{
    if(groups[r.status]) groups[r.status].push(nameFor(r.user_id));
  });
  return groups;
}
function myRsvpFor(eventId){
  const row = state.rsvps.find(r=>r.event_id===eventId && r.user_id===state.session.user.id);
  return row ? row.status : null;
}

function renderCalendar(){
  const officer = isOfficer();
  const y = state.calendarYear, m = state.calendarMonth;
  const first = firstWeekdayOfMonth(y,m);
  const numDays = daysInMonth(y,m);
  const prevMonthDays = daysInMonth(m===0?y-1:y, m===0?11:m-1);
  const cells = [];
  for(let i=0;i<42;i++){
    const offset = i - first;
    let cy=y, cm=m, cd;
    if(offset < 0){ cd = prevMonthDays + offset + 1; cm = m===0?11:m-1; cy = m===0?y-1:y; }
    else if(offset >= numDays){ cd = offset - numDays + 1; cm = m===11?0:m+1; cy = m===11?y+1:y; }
    else { cd = offset + 1; }
    cells.push({ iso: isoFromParts(cy,cm,cd), day: cd, inMonth: offset>=0 && offset<numDays });
  }
  const today = todayISO();
  const eventsByDate = {};
  state.events.forEach(ev=>{ (eventsByDate[ev.date] = eventsByDate[ev.date] || []).push(ev); });

  return `
    ${pageBanner('Raid Calendar')}
    <div class="eyebrow sans">Schedule</div>
    <h2 class="page-title">Raid calendar</h2>
    <p class="page-sub sans">Click any event to see details and mark yourself down for the night.</p>

    <div class="cal-ornate-frame">
      <div class="ornate-corner tl"></div>
      <div class="ornate-corner tr"></div>
      <div class="ornate-corner bl"></div>
      <div class="ornate-corner br"></div>

      <div class="cal-header">
        <div class="cal-nav">
          <button class="cal-nav-btn" id="cal-prev">&lsaquo;</button>
          <div class="cal-month-label">${MONTH_NAMES[m]}<span class="cal-month-year"> ${y}</span></div>
          <button class="cal-nav-btn" id="cal-next">&rsaquo;</button>
          <button class="btn secondary" id="cal-today" style="margin-left:6px;">Today</button>
        </div>
        ${ officer ? `<button class="btn" id="cal-add-event">+ Add event</button>` : '' }
      </div>

      <div class="cal-grid">
        ${ WEEKDAY_LABELS.map(w=>`<div class="cal-weekday">${w}</div>`).join('') }
        ${ cells.map(c=>{
          const evs = eventsByDate[c.iso] || [];
          const isPast = c.iso < today;
          const isUpcoming = c.iso >= today && evs.length > 0;
          return `
          <div class="cal-cell ${c.inMonth?'':'other-month'} ${c.iso===today?'today':''} ${isPast?'past':''} ${isUpcoming?'upcoming':''}">
            <div class="cal-daynum">${c.day}</div>
            <div class="cal-events">
              ${ evs.map(ev=>`
                <button class="cal-event-pill ${isPast?'past-event':''}" data-open-event="${ev.id}">
                  <span class="cal-event-title">${esc(ev.title)}</span>
                </button>
              `).join('') }
            </div>
            ${ !c.inMonth ? '' : (evs.length === 0 ? `<div class="cal-empty-indicator"></div>` : '') }
            ${ officer ? `<button class="cal-add-btn" data-adddate="${c.iso}" title="Add event">+</button>` : '' }
          </div>`;
        }).join('') }
      </div>
    </div>
  `;
}

function renderModal(){
  if(!state.modal) return '';
  if(state.modal.type === 'add-event') return renderAddEventModal(state.modal.date||'');
  if(state.modal.type === 'event-detail') return renderEventDetailModal(state.modal.eventId);
  if(state.modal.type === 'assign-slot') return renderAssignSlotModal(state.modal.groupIdx, state.modal.slotIdx);
  if(state.modal.type === 'pick-image') return renderPickImageModal(state.modal.slotKey);
  if(state.modal.type === 'shop') return renderShopModal();
  return '';
}

function renderShopModal(){
  const officer = isOfficer();
  const gold = state.profile ? (state.profile.gold||0) : 0;
  const myLevel = state.profile ? (state.profile.discord_rank_level||0) : 0;

  const rankItems = state.shopItems.filter(i=>i.category==='rank').sort((a,b)=>(a.rank_order||0)-(b.rank_order||0));
  const iconItems = state.shopItems.filter(i=>i.category==='discord_icon');
  const titleItems = state.shopItems.filter(i=>i.category==='discord_title');
  const nameCustomItems = state.shopItems.filter(i=>i.category==='name_customization');
  const stickerImages = state.galleryImages.filter(g=>g.is_sticker);
  const stickerPrice = state.settings.sticker_price != null ? state.settings.sticker_price : 25;

  function renderEditForm(item){
    return `
      <div class="shop-card">
        <div id="shop-edit-form-${item.id}">
          <div class="field"><label>Name</label><input name="name" value="${esc(item.name)}"></div>
          <div class="field"><label>Description</label><textarea name="description">${esc(item.description||'')}</textarea></div>
          <div class="field"><label>Cost (gold)</label><input name="cost" type="number" min="0" value="${item.cost}"></div>
          <div style="display:flex; gap:8px;">
            <button class="btn secondary" type="button" data-save-shop-item="${item.id}">Save</button>
            <button class="btn secondary" type="button" data-cancel-shop-edit>Cancel</button>
          </div>
        </div>
      </div>`;
  }

  function renderSimpleCard(item){
    if(state.editingShopItemId === item.id) return renderEditForm(item);
    const canAfford = gold >= item.cost;
    return `
      <div class="shop-card ${item.active===false?'inactive':''}">
        <div class="shop-card-name">${esc(item.name)}</div>
        <div class="shop-card-desc muted sans">${esc(item.description||'')}</div>
        <div class="shop-card-footer">
          <span class="nav-gold-badge">&#10022; ${item.cost}</span>
          ${ officer ? `<button class="btn secondary" type="button" data-edit-shop-item="${item.id}">Edit</button>` : '' }
        </div>
        <button class="btn" type="button" data-buy-shop-item="${item.id}" ${ (!canAfford || item.active===false) ? 'disabled' : '' } style="width:100%; margin-top:10px;">
          ${ item.active===false ? 'Unavailable' : (canAfford ? 'Redeem' : 'Not enough gold') }
        </button>
      </div>`;
  }

  function renderRankCard(item){
    if(state.editingShopItemId === item.id) return renderEditForm(item);
    const order = item.rank_order || 0;
    const owned = order <= myLevel;
    const isNext = order === myLevel + 1;
    const canAfford = gold >= item.cost;
    let buttonLabel = 'Locked';
    let disabled = true;
    if(owned){ buttonLabel = 'Owned'; disabled = true; }
    else if(isNext){ buttonLabel = canAfford ? 'Redeem' : 'Not enough gold'; disabled = !canAfford; }
    return `
      <div class="shop-card ${owned?'':(isNext?'':'inactive')}">
        <div class="shop-card-name">Rank ${order}: ${esc(item.name)}</div>
        <div class="shop-card-desc muted sans">${esc(item.description||'')}</div>
        <div class="shop-card-footer">
          <span class="nav-gold-badge">&#10022; ${item.cost}</span>
          ${ officer ? `<button class="btn secondary" type="button" data-edit-shop-item="${item.id}">Edit</button>` : '' }
        </div>
        ${ owned ? `<div class="shop-owned-badge">&#10003; Owned</div>` :
          `<button class="btn" type="button" data-buy-rank="${item.id}" ${disabled?'disabled':''} style="width:100%; margin-top:10px;">${buttonLabel}</button>`
        }
      </div>`;
  }

  function renderStickerCard(img){
    const price = img.sticker_price != null ? img.sticker_price : stickerPrice;
    const canAfford = gold >= price;
    return `
      <div class="shop-card sticker-shop-card">
        <img src="${esc(img.url)}" alt="${esc(img.caption||'')}" class="shop-sticker-preview">
        <div class="shop-card-name">${esc(img.caption||'Sticker')}</div>
        <div class="shop-card-footer">
          <span class="nav-gold-badge">&#10022; ${price}</span>
          ${ officer ? `<button class="btn secondary" type="button" data-edit-sticker-price="${img.id}|${price}" style="font-size:11px; padding:4px 8px;">Edit</button>` : '' }
        </div>
        <button class="btn" type="button" data-buy-sticker="${img.id}" ${canAfford?'':'disabled'} style="width:100%; margin-top:10px;">
          ${ canAfford ? 'Place on Wall' : 'Not enough gold' }
        </button>
      </div>`;
  }

  return `
  <div class="modal-backdrop" id="modal-backdrop">
    <div class="modal-panel" id="modal-panel" style="max-width:820px;">
      <div class="modal-header">
        <h3>Reward Shop</h3>
        <button class="modal-x" id="modal-close">&times;</button>
      </div>
      <div class="nav-gold-badge" style="margin-bottom:16px;">&#10022; ${gold} gold available</div>

      <div class="shop-section">
        <h4 class="shop-section-title">Discord Rank Upgrades</h4>
        <p class="muted sans" style="font-size:12px; margin-bottom:12px;">Purchase in order — each rank unlocks the next. The Discord bot will apply these automatically once it's connected.</p>
        ${ rankItems.length ? `<div class="shop-grid">${rankItems.map(renderRankCard).join('')}</div>` : emptyState('No ranks set up yet.') }
      </div>

      <div class="shop-section">
        <h4 class="shop-section-title">Sticker Wall</h4>
        <p class="muted sans" style="font-size:12px; margin-bottom:12px;">Place a sticker on the wall with your name under it — stickers stay up permanently for now.</p>
        ${ officer ? `
        <div class="field" style="max-width:220px; margin-bottom:14px;">
          <label>Sticker price (gold)</label>
          <div style="display:flex; gap:8px;">
            <input type="number" min="0" id="sticker-price-input" value="${stickerPrice}">
            <button class="btn secondary" type="button" id="save-sticker-price-btn">Save</button>
          </div>
        </div>` : '' }
        ${ stickerImages.length ? `<div class="shop-grid">${stickerImages.map(renderStickerCard).join('')}</div>` :
          emptyState(officer ? 'No images are flagged as stickers yet — go to the Gallery to enable some.' : 'No stickers available yet.') }
      </div>

      <div class="shop-section">
        <h4 class="shop-section-title">Roster Name Customization</h4>
        <p class="muted sans" style="font-size:12px; margin-bottom:12px;">Make your roster name stand out with special effects and animations.</p>
        ${ nameCustomItems.length ? `<div class="shop-grid">${nameCustomItems.map(renderSimpleCard).join('')}</div>` : emptyState('No name customizations set up yet.') }
      </div>

      <div class="shop-section">
        <h4 class="shop-section-title">Discord Icons</h4>
        <p class="muted sans" style="font-size:12px; margin-bottom:12px;">The Discord bot will apply these automatically once it's connected.</p>
        ${ iconItems.length ? `<div class="shop-grid">${iconItems.map(renderSimpleCard).join('')}</div>` : emptyState('No icons set up yet.') }
      </div>

      <div class="shop-section">
        <h4 class="shop-section-title">Custom Guild Discord Titles</h4>
        <p class="muted sans" style="font-size:12px; margin-bottom:12px;">The Discord bot will apply these to your nickname automatically once it's connected.</p>
        ${ titleItems.length ? `<div class="shop-grid">${titleItems.map(renderSimpleCard).join('')}</div>` : emptyState('No titles set up yet.') }
      </div>
    </div>
  </div>`;
}
function renderPickImageModal(slotKey){
  return `
  <div class="modal-backdrop" id="modal-backdrop">
    <div class="modal-panel" id="modal-panel" style="max-width:600px;">
      <div class="modal-header">
        <h3>Choose an image</h3>
        <button class="modal-x" id="modal-close">&times;</button>
      </div>
      ${ state.galleryImages.length ? `
        <div class="gallery-picker-grid">
          ${ state.galleryImages.map(g=>`
            <button type="button" class="gallery-picker-item" data-pick-image="${g.id}" data-pick-url="${esc(g.url)}" title="${esc(g.caption||'')}">
              <img src="${esc(g.url)}" alt="${esc(g.caption||'')}" loading="lazy">
            </button>
          `).join('') }
        </div>
      ` : `<div class="empty sans">No images uploaded yet. Go to the Gallery page to upload one first.</div>` }
    </div>
  </div>`;
}


function renderAddEventModal(prefillDate){
  return `
  <div class="modal-backdrop" id="modal-backdrop">
    <div class="modal-panel" id="modal-panel">
      <div class="modal-header">
        <h3>Schedule an event</h3>
        <button class="modal-x" id="modal-close">&times;</button>
      </div>
      <div id="event-form">
        <div class="row">
          <div class="field"><label>Title</label><input name="title" placeholder="e.g. Hyjal Summit clear" required></div>
          <div class="field"><label>Date</label><input name="date" type="date" value="${esc(prefillDate)}" required></div>
        </div>
        <div class="row">
          <div class="field"><label>Time (optional)</label><input name="time" placeholder="e.g. 8:00 PM server"></div>
          <div class="field"><label>Instance (optional)</label><input name="instance" placeholder="e.g. Onyxia's Lair"></div>
        </div>
        <div class="field"><label>Notes (optional)</label><textarea name="notes" placeholder="Invites go out 30 min early, bring flasks"></textarea></div>
        <div id="event-error" class="field-error" style="display:none;"></div>
        <button class="btn" type="button" id="event-form-btn">Add to calendar</button>
      </div>
    </div>
  </div>`;
}

function renderEventDetailModal(eventId){
  const ev = state.events.find(e=>e.id===eventId);
  if(!ev) return '';
  const officer = isOfficer();
  const mine = myRsvpFor(ev.id);
  const groups = rsvpGroupsFor(ev.id);
  function nameList(arr){ return arr.length ? esc(arr.join(', ')) : '<span class="muted">nobody yet</span>'; }
  return `
  <div class="modal-backdrop" id="modal-backdrop">
    <div class="modal-panel" id="modal-panel">
      <div class="modal-header">
        <h3>${esc(ev.title)}</h3>
        <button class="modal-x" id="modal-close">&times;</button>
      </div>
      <div class="muted" style="margin-bottom:14px;"><span class="mono">${fmtDate(ev.date)}${ev.time?' &middot; '+esc(ev.time):''}</span>${ev.instance?' &middot; '+esc(ev.instance):''}</div>
      ${ ev.notes ? `<div style="margin-bottom:16px; line-height:1.6; white-space:pre-wrap;">${esc(ev.notes)}</div>` : '' }

      <div class="rule"></div>
      <div style="font-size:12px; font-weight:700; text-transform:uppercase; color:var(--text-muted); margin-bottom:10px;">Your RSVP</div>
      <div class="rsvp-btns" style="margin-bottom:18px;">
        <button class="rsvp-btn ${mine==='going'?'sel-going':''}" data-modal-rsvp="going">Going</button>
        <button class="rsvp-btn ${mine==='maybe'?'sel-maybe':''}" data-modal-rsvp="maybe">Maybe</button>
        <button class="rsvp-btn ${mine==='out'?'sel-out':''}" data-modal-rsvp="out">Can't make it</button>
      </div>

      <div class="rule"></div>
      <div style="margin-top:14px;">
        <div style="margin-bottom:8px;"><span class="badge going"><span class="mono">${groups.going.length}</span> going</span> ${nameList(groups.going)}</div>
        <div style="margin-bottom:8px;"><span class="badge maybe"><span class="mono">${groups.maybe.length}</span> maybe</span> ${nameList(groups.maybe)}</div>
        <div style="margin-bottom:8px;"><span class="badge out"><span class="mono">${groups.out.length}</span> out</span> ${nameList(groups.out)}</div>
      </div>

      ${ officer ? `
      <div class="rule"></div>
      <button class="btn danger" data-modal-delete-event="${ev.id}">Remove event</button>` : '' }
    </div>
  </div>`;
}

function renderAssignSlotModal(groupIdx, slotIdx){
  const sel = state.selectedSpec;
  if(!sel) return '';
  const slot = state.compSlots.find(s=>s.group_index===groupIdx && s.slot_index===slotIdx);
  const cls = CLASS_SPECS[sel.classKey];
  const specLabel = cls.specs.find(s=>s.key===sel.specKey).label;
  return `
  <div class="modal-backdrop" id="modal-backdrop">
    <div class="modal-panel" id="modal-panel">
      <div class="modal-header">
        <h3>Group ${groupIdx+1} — Slot ${slotIdx+1}</h3>
        <button class="modal-x" id="modal-close">&times;</button>
      </div>
      <div style="display:flex; align-items:center; gap:10px; margin-bottom:18px;">
        <span class="spec-icon-sm" style="${specIconStyle(sel.classKey)}">${specIconHtml(sel.classKey, sel.specKey)}</span>
        <div>
          <div style="font-weight:700;">${esc(cls.label)}</div>
          <div class="muted" style="font-size:12px;">${esc(specLabel)}</div>
        </div>
      </div>
      <div class="field">
        <label>Raider name</label>
        <input id="assign-slot-name" placeholder="Character name" value="${esc(slot?slot.character_name:'')}">
      </div>
      <div id="assign-slot-error" class="field-error" style="display:none;"></div>
      <div style="display:flex; gap:10px;">
        <button class="btn" type="button" id="assign-slot-save">${slot?'Update':'Assign'}</button>
        ${ slot ? `<button class="btn danger" type="button" id="assign-slot-clear">Clear slot</button>` : '' }
      </div>
    </div>
  </div>`;
}

