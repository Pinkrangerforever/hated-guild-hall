/* Guild War rule book: the sections shown in the war room's pamphlet. Each section has an id, a title, an icon,
   the text (simple HTML) and extra search words. Keep the numbers in step with RULES in engine.js. */
const WAR_RULEBOOK = [
  { id: 'overview', icon: '⚔', title: 'The War at a Glance', tags: 'overview basics week horde alliance goal win',
    body: `<p>Every week the guild splits into the <b>Horde</b> and the <b>Alliance</b> and fights over the map of Azeroth.
      Take zones, hold whole regions, build outposts and strongholds, and out-score the other side by the end of the week.</p>
      <ul><li><b>Sign-ups:</b> Sunday 8pm to midnight.</li><li><b>The war:</b> Monday 12:00am to Sunday 8pm.</li>
      <li>When the war ends the side with the higher <b>war score</b> wins, and both sides earn site rewards.</li></ul>` },
  { id: 'teams', icon: '🛡', title: 'Teams & Joining', tags: 'teams draft snake activity join late smaller sign up',
    body: `<p>At midnight on Sunday everyone who signed up is split by a <b>snake draft</b> on activity, so both sides get a fair mix of regulars and casual players.</p>
      <p>You can join at any time during the week: you go to the <b>smaller team</b> and start with that day's <b>5 action points</b> and the same <b>reinforcements</b> your teammates got that morning (region bonuses included). You get your first share of resources at the next dawn.</p>
      <p>Troops are shared by the whole faction. Your own <b>action points</b>, <b>reinforcements</b>, <b>resources</b> and <b>cards</b> are yours.</p>` },
  { id: 'map', icon: '🗺', title: 'The Map', tags: 'map zones regions capitals ports routes boats zeppelins borders neutral',
    body: `<p>43 zones across Kalimdor and the Eastern Kingdoms. Zones next to each other on the map are connected, and so are the ends of every <b>boat</b> and <b>zeppelin</b> route.</p>
      <ul><li><b>Neutral zones</b> start with 2 to 4 defenders and fly the yellow banner.</li>
      <li><b>Capitals</b> (Orgrimmar, Thunder Bluff, Undercity, Stormwind, Ironforge, Darnassus) are marked with a crown ♛. They have no special dice bonus.</li>
      <li><b>Ports</b> (any zone a boat route lands in) let your whole faction trade at 3:1.</li>
      <li><b>Regions:</b> hold every zone in a region for bonus troops each day and bonus points:
        Northern Kalimdor +5 / 4 pts, Kalimdor Heartland +3 / 2 pts, Southern Wilds +3 / 2 pts, Lordaeron +4 / 3 pts, The Heartlands +5 / 4 pts, Southern Kingdoms +5 / 4 pts. Hover over a zone to see its whole region glow.</li></ul>` },
  { id: 'ap', icon: '◆', title: 'Action Points', tags: 'action points ap day reset cost free',
    body: `<p>You get <b>5 action points</b> (AP) a day. They refill at midnight and don't carry over.</p>
      <table><tr><td>Attack</td><td>1 AP</td></tr><tr><td>Move</td><td>1 AP</td></tr><tr><td>Fortify</td><td>1 AP</td></tr><tr><td>Build an outpost / stronghold</td><td>1 AP</td></tr>
      <tr><td>Deploy troops</td><td>free</td></tr><tr><td>Craft a card, trade, use Shield Wall</td><td>free</td></tr></table>` },
  { id: 'troops', icon: '🪖', title: 'Troops & Reinforcements', tags: 'troops reinforcements deploy fresh ready rest sleep stronghold connected',
    body: `<p>Each day at dawn every player gets reinforcements: <b>3, +1 for every 3 zones</b> your faction holds, <b>+ region bonuses</b>.
      (If one team is bigger, its players get a little less each so both sides grow at about the same rate.)</p>
      <p><b>Deploying</b> is free. You can only deploy to zones linked to one of your <b>strongholds</b> through your own territory. Deploy one at a time, or all at once. <b>Deployed troops are ready ⚔ straight away</b>: you can attack with them the same day.</p>
      <p><b>🔭 Scout reports:</b> the day has three watches (midnight to 8am, 8am to 4pm, 4pm to midnight). The first time you open the war room in each watch you get <b>1 extra troop</b>. Missed watches don't carry over.</p>
      <p>Troops that <b>move</b> or <b>capture a zone</b> arrive <b>fresh 💤</b>: they can defend, but can't move or attack again until the next dawn. Ready troops show as ⚔.</p>` },
  { id: 'pets', icon: '🐾', title: 'Pets', tags: 'pet pets level respawn guard station companion',
    body: `<p>Your hatched site pet fights for your faction. Station it in one of your zones (free, and it can move once a day). Only one pet can guard each zone.</p>
      <ul><li>It counts as <b>one more troop</b> in that zone, and joins attacks made from it.</li>
      <li>In every round of a battle it fights in, it adds <b>+1 to its side's lowest die</b>.</li>
      <li>It is always the <b>last</b> of its side to fall. If it wins an attack, it moves into the captured zone.</li>
      <li>A fallen pet recovers in <b>24 hours at level 1</b>, down to <b>12 hours at level 10</b>, then can be stationed again.</li></ul>` },
  { id: 'move', icon: '🥾', title: 'Moving', tags: 'move march once per day connected forced',
    body: `<p>Move <b>ready</b> troops between your own zones that are connected through your territory. Costs 1 AP.</p>
      <ul><li>Each zone can send troops out <b>once a day</b> (a <b>Forced March</b> card lets it go again).</li>
      <li>At least <b>one troop must stay behind</b>.</li><li>Moved troops arrive <b>fresh 💤</b>.</li></ul>` },
  { id: 'attack', icon: '⚔', title: 'Attacking & Dice', tags: 'attack battle dice roll defender attacker capture risk ties combat',
    body: `<p>Attack a bordering zone (or across a route) with ready troops. Costs 1 AP. The battle is fought out at once in rounds:</p>
      <ul><li>The attacker rolls up to <b>3 dice</b> (one per attacking troop), the defender up to <b>2</b> (<b>3</b> with an outpost or stronghold).</li>
      <li>Highest die faces highest, second faces second. <b>Ties go to the defender.</b> Each lost pair kills one troop.</li>
      <li>Defender bonuses add to their <b>best</b> die: +1 fortified, +1 stronghold.</li>
      <li>Rounds repeat until one side runs out. If the defenders fall, your surviving attackers <b>capture</b> the zone and arrive fresh.</li>
      <li>Defenders lose fresh troops before ready ones. Survivors of a failed attack fall back home.</li></ul>` },
  { id: 'fortify', icon: '🧱', title: 'Fortify', tags: 'fortify wall defence defense 24 hours stack',
    body: `<p>Costs 1 AP: the zone's defenders get <b>+1 to their best die</b> for <b>24 hours</b> from when you cast it.</p>
      <ul><li>A zone can't be fortified again while it already is.</li><li>The fortification is <b>broken</b> if the zone is captured.</li>
      <li>A <b>Naval Landing</b> ignores it.</li></ul>` },
  { id: 'resources', icon: '💰', title: 'Resources & Deposits', tags: 'resources food wood ore gold deposit rich production income share',
    body: `<p>Four resources: <b>food</b>, <b>wood</b>, <b>ore</b> and <b>gold</b>. Every zone has a resource type, but only this war's
      <b>rich deposits</b> produce (3 per resource on each continent, picked fresh every war; they show their icon in a gold ring).</p>
      <ul><li>A held rich deposit makes <b>2 a day</b>, <b>+1</b> with an outpost, <b>+2</b> with a stronghold.</li>
      <li>Each dawn your faction's production is shared among teammates who played in the last day.</li></ul>` },
  { id: 'build', icon: '🏰', title: 'Outposts & Strongholds', tags: 'build outpost stronghold upgrade cost deploy',
    body: `<table><tr><td><b>Outpost</b></td><td>1 wood + 1 food + 1 ore, 1 AP</td></tr><tr><td><b>Stronghold</b> (upgrade an outpost)</td><td>2 ore + 2 wood + 1 gold, 1 AP</td></tr></table>
      <ul><li>Outposts and strongholds give defenders a <b>third die</b>.</li><li>Strongholds also add <b>+1 to the best defence die</b> and are where you can <b>deploy</b> from.</li>
      <li>Both raise a rich deposit's production. Both are lost if the zone is captured.</li>
      <li>Each side starts with 4 strongholds (2 per continent).</li></ul>` },
  { id: 'cards', icon: '🃏', title: 'Battle Cards', tags: 'cards warcry shield wall forced march naval landing troops craft',
    body: `<p>Craft cards from resources (free, no AP) and play them when you need them:</p>
      <table><tr><td>📯 <b>Warcry</b></td><td>1 wood + 1 ore</td><td>+1 attack die for one battle.</td></tr>
      <tr><td>🛡 <b>Shield Wall</b></td><td>1 ore + 1 food</td><td>Raise on one of your zones: the next attack on it loses its best die in the first round.</td></tr>
      <tr><td>🥾 <b>Forced March</b></td><td>1 food + 1 wood</td><td>Move from a zone that already sent troops today.</td></tr>
      <tr><td>⛵ <b>Naval Landing</b></td><td>2 wood + 1 food</td><td>Attack across a boat or zeppelin route ignoring all defender bonuses.</td></tr>
      <tr><td>🪖 <b>+2 Troops</b></td><td>1 food + 1 ore</td><td>Two extra reinforcements right away.</td></tr></table>` },
  { id: 'trade', icon: '⚖', title: 'Trading', tags: 'trade bank port exchange rate 4:1 3:1',
    body: `<p>Trade with the bank at any time, for free: <b>4 of one resource for 1 of another</b>, or <b>3 for 1</b> if your faction holds a port.</p>` },
  { id: 'autopilot', icon: '🤖', title: 'Autopilot', tags: 'autopilot afk idle inactive 11:59 fortify',
    body: `<p>If you don't do anything on a day, at <b>11:59pm</b> autopilot steps in for you:</p>
      <ul><li>Your waiting reinforcements are placed on the zones under the most threat.</li><li><b>2 of your AP</b> fortify two of your faction's zones that aren't fortified.</li>
      <li>It never attacks, moves, builds or spends resources.</li></ul>` },
  { id: 'scoring', icon: '🏆', title: 'Scoring & Victory', tags: 'score points victory win zones outposts strongholds regions daily lead end',
    body: `<p>The war score, counted when the war ends on Sunday at 8pm:</p>
      <table><tr><td>Each zone held</td><td>1</td></tr><tr><td>Each outpost</td><td>1</td></tr><tr><td>Each stronghold</td><td>2</td></tr>
      <tr><td>Each enemy starting stronghold you hold</td><td>3</td></tr><tr><td>Each whole region</td><td>2 to 4</td></tr><tr><td>Each day you ended holding more zones</td><td>1</td></tr></table>
      <p><b>Your personal score</b> (for the champions list and MVP): 5 per capture, 1 per enemy troop killed, 3 per outpost, 6 per stronghold, 1 per fortify.</p>` },
  { id: 'interface', icon: '📜', title: 'The War Room', tags: 'interface help ledger feed chat replay camera controls',
    body: `<ul><li><b>Camera:</b> drag to pan, right-drag (or shift-drag) to turn, scroll to zoom.</li>
      <li><b>Click a zone</b> for its details and your orders.</li>
      <li><b>War feed:</b> everything that has happened. When you come back, moves since your last visit replay in order.</li>
      <li><b>Ledger:</b> who is on which side, and who has acted today.</li>
      <li><b>Chat:</b> board chat is open to everyone; faction chat only to your side.</li></ul>` }
];
if(typeof module !== 'undefined') module.exports = { WAR_RULEBOOK };
