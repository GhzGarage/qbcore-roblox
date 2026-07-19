# Project Status

Last updated: July 18, 2026.

This is a from-scratch Roblox/Luau port of the QBCore pieces needed for a
playable join-to-character flow. It now has several working resource slices, but
it is still not a full QBCore ecosystem.

## Accomplished So Far

- [x] Rojo project layout and serve workflow, with cleanup/setup helpers for
      Studio-imported objects.
- [x] Shared QBCore-style modules for config, items, jobs, crews, vehicles, and
      remotes.
- [x] DataStore-backed account profile loading with lightweight session locks.
- [x] Character list, create, select, delete, and spawn flow.
- [x] Per-account multi-character storage with generated citizen IDs and an
      offline citizen-index lookup.
- [x] Server-owned Player object with money, job, crew, metadata, inventory,
      save, notify, and logout helpers.
- [x] Client PlayerData cache with bindable update signals.
- [x] Basic character select/create/delete UI.
- [x] Saved Roblox avatar appearance editor:
      per-character HumanoidDescription serialization, live preview, save/cancel,
      accessory limits, scale clamps, and optional ownership validation.
- [x] Categorized clothing, accessory, barber, and wardrobe shops with invisible
      proximity-prompt anchors, saved per-character outfits, and revocable global
      clothing-only share codes.
- [x] Server-authoritative hunger/thirst status loop.
- [x] Configurable job-grade paychecks with duty gating, optional banking-backed
      society debits, and a `/duty` toggle.
- [x] Personal, player-shared, and boss-accessible organization banking with
      bank/ATM proximity prompts, deposits/withdrawals, online or queued citizen-ID
      transfers, cards/PINs, daily ATM limits, and persistent statements.
- [x] HUD for identity, job, cash/bank, health, armor, hunger, thirst, and
      equipped weapon ammo.
- [x] Toast notification UI.
- [x] Shared Roblox-native proximity prompt UI for keyboard, gamepad, and touch,
      reused by banks, shops, garages, management, clothing, and other world
      interactions.
- [x] Player inventory and hotbar:
      30 slots, 5-slot hotbar, weights, stacks, starter items, move/use/give
      actions, and server-authoritative helpers.
- [x] Inventory-backed item shops with configurable catalogs, pricing, session
      stock, quantity purchases, previews, and job/crew/license restrictions.
- [x] Consumable item support for hunger/thirst.
- [x] Medical item support:
      bandages, armor, EMS-only first aid revives, death tracking, death screen,
      respawn delay, configured respawn behavior, and optional inventory wipe.
- [x] Weapon item support:
      inventory-backed Roblox Tool equip/holster, template collection, per-weapon
      config overrides, ammo item economy, loaded ammo persistence, no-ammo
      reload guard, local crosshair patch helper, and weapon damage routed
      through the medical armor/death path.
- [x] Access control:
      closed server flag, whitelist, DataStore-backed bans, and graded
      user/mod/admin/god permissions.
- [x] TextChatService command router and default commands:
      `/commands`, `/id`, `/logout`, `/appearance`, `/emotes`, `/music`,
      `/musicsearch`, `/job`, `/duty`, `/crew`, `/cash`, `/bank`, `/admin`, `/setjob`,
      `/setcrew`, `/givemoney`, `/setmoney`, `/giveitem`, `/car`, `/dv`,
      `/time`, `/freezetime`, `/kick`, and `/ban`.
- [x] Native admin menu:
      dashboard, player details, goto/bring/heal/kick/ban, money/job/crew/item
      actions, vehicle spawning, time controls, logs, and developer position tools.
- [x] Time sync:
      configurable day length, `/time`, `/freezetime`, server-applied world
      environment, and client-side time-of-day visual grading.
- [x] Weather sync:
      server-owned weather state, automatic cycling, clear/clouds/overcast/fog/
      rain/thunder/snow presets, synced transitions, local precipitation,
      lightning flashes, `/weather`, `/freezeweather`, `/blackout`, admin
      Environment controls, and tagged-light blackout support.
- [x] Vehicle registry and first-pass vehicle spawning:
      shared vehicle catalog, ServerStorage template folder, spawned vehicle
      folder, spawn/delete commands, admin vehicle catalog, plates, attributes,
      aliases, and template-name matching.
- [x] Free-use vehicle dealership with four anchored showroom displays, catalog
      browsing, timed test drives, persistent character ownership, future-ready
      financing, and finance-desk vehicle release.
- [x] Public garage system with proximity prompts, per-garage storage, owned-only
      deposit validation, state/condition persistence, spawn occupancy checks,
      retrieval, and automatic return on disconnect.
- [x] Standalone job/crew management with indexed rosters, nearby hiring, grade
      changes, removal, offline queues, shared banking funds, and outfit access.
- [x] Inventory-opened StudOS smartphone with filtered private messaging,
      eligible voice calls, social posts, camera captures, and per-character state.
- [x] Native QBMenu-style client menu controller for other resources.
- [x] Emote menu using Roblox avatar emotes through QBMenu.
- [x] Stage speaker music system:
      shared stations/tracks, proximity-gated server playback, volume controls,
      Creator Store audio search, and client audio bridge/menu.

## Checklist: Left To Do

### Foundation And Production Hardening

- [ ] Replace the small local `ProfileStore.lua` with a battle-tested production
      profile library, or harden it with retries, telemetry, conflict handling,
      and migration/version metadata.
- [ ] Add automated Luau/static checks and a repeatable Studio smoke-test script
      for remotes, character flow, inventory, commands, and admin actions.
- [ ] Add structured server logs/audit persistence for admin actions, money/item
      mutations, deaths, bans, and DataStore failures.
- [ ] Add data migration helpers for future schema changes.
- [ ] Decide which systems need cross-server/offline access and create safe
      read/write APIs for them.
- [ ] Localize player-facing strings; most UI/notifications are inline English.

### Character And Session Flow

- [ ] Implement true in-session character switching instead of saving and kicking
      on `/logout`.
- [ ] Expand character creation fields beyond first/last name:
      birthdate, gender, nationality, and optional backstory fields. Phone numbers
      are already generated automatically when a character loads.
- [ ] Add spawn-selection support once apartments/housing/hospitals/garages exist.
- [ ] Add stronger character deletion cleanup for external per-character records
      such as phone-directory claims and future houses or warrants. Owned vehicles
      are profile-local, and outfit share codes are already removed with a character.

### Inventory, Items, And Economy

- [x] Build inventory-backed item shops with buy pricing, server-session stock,
      job/crew/license restrictions, quantity controls, and item previews.
- [ ] Add shop sell pricing, persistent/cross-server stock, and optional restocking
      gameplay if the economy eventually needs it.
- [ ] Build world drops with pickup, decay/despawn, ownership timing, and anti-dupe
      safeguards.
- [ ] Build stashes, trunks, gloveboxes, and shared containers on top of the
      existing slot/item helpers.
- [ ] Build crafting/recipes and item metadata flows for tools, serial numbers,
      licenses, durability, and quality.
- [x] Add paychecks using job grade payment and `Config.Money.PayCheckTimeOut`.
- [x] Add society/business accounts and connect optional society-funded paychecks.
- [x] Add banking UI, account history, cash deposit/withdrawal, and online or
      safely queued offline citizen-ID transfer workflows.
- [x] Add ATM cards/PINs and optional daily withdrawal limits.

### Jobs, Crews, And Gameplay Loops

- [x] Add proximity-prompt job/crew management with indexed rosters, nearby
      hiring, grade changes, removal, and offline change queues; shared funds live in banking.
- [ ] Turn the current job/crew registries into real gameplay systems with map
      duty prompts, blips, role permissions, and grade-specific actions.
- [ ] Port or redesign core jobs:
      police, ambulance, mechanic, taxi, delivery/trucker, garbage, and civilian
      activities.
- [ ] Add reports, calls, dispatch, panic buttons, fines, warrants, and evidence
      systems for public-service roles.
- [ ] Add crew progression/reputation and crew-only activities.

### Vehicles

- [ ] Install or build Roblox vehicle templates for every catalog entry in
      `QBShared/Vehicles.lua`.
- [x] Add persistent character-owned vehicle records and dealership spawn limits.
- [x] Add public garage storage/retrieval and persistent in/out garage assignment.
- [ ] Add impound/depot release, persistent world parking, and job/house garages.
- [ ] Add keys/locks, ownership checks, hotwire/lockpick flow, carjacking rules,
      and police access rules.
- [ ] Add fuel consumption/refill, repair state, damage persistence, and cleanup
      for abandoned spawned vehicles.
- [ ] Wire trunks/gloveboxes to the inventory container system.
- [x] Add dealership/purchase flow and shared vehicle prices (currently `$0`).

### Weapons And Combat

- [ ] Install/test Roblox Tool templates for every configured weapon item, not
      only the initial weapon-kit imports.
- [ ] Add weapon licenses, job restrictions, serial numbers, durability, evidence,
      recoil/balance passes, and safe-zone rules.
- [ ] Finish the sample weapon/ammo shop with license issuance and add police
      armory workflows.
- [ ] Add downed/last-stand behavior if desired; current medical flow is death
      screen plus respawn/revive.
- [ ] Add combat logging/admin review tools for damage events.

### World, Weather, And Environment

- [ ] Polish weather effects with custom rain/snow textures, puddles/wet surfaces,
      thunder audio assets, shelter checks, and interior/exterior attenuation.
- [ ] Expand blackout beyond tagged Light instances if the map uses neon meshes,
      beam signs, screens, or custom lighting scripts.
- [ ] Add map-aware spawn/hospital/police/garage/stage configuration instead of
      hard-coded test coordinates.
- [ ] Add place asset validation for required folders, stage speaker paths,
      vehicle templates, weapon templates, weather blackout tags, and Lighting
      requirements.

### UI And Client Experience

- [ ] Finish currently blank admin tabs:
      Reports, Chat, and Leaderboard.
- [ ] Add admin moderation tools for reports/chat/player history beyond the current
      action log.
- [ ] Add mobile/gamepad polish across character select, appearance, inventory,
      admin, menu, emotes, and stage music.
- [ ] Add settings/keybinds for inventory, hotbar, admin, emotes, music, and
      respawn controls.
- [ ] Add consistent UI theming/components so each LocalScript is not carrying its
      own duplicated UI helpers forever.

### QBCore Ecosystem Coverage

- [ ] Housing/apartments.
- [ ] Impound/depot plus job/house garages beyond the public garage system.
- [x] Inventory-backed smartphone with messaging, eligible voice calls, social
      posts, camera captures, settings, and persistent per-character state.
- [x] Management/boss menu for job employees and crew members, including grades,
      nearby hiring/firing, offline change queues, and shared banking funds.
- [ ] Door locks.
- [ ] General-purpose target/interact abstraction beyond the existing configured
      Roblox ProximityPrompt interactions.
- [ ] Progress bars/skill checks/minigames.
- [ ] Dispatch/radio.
- [ ] Crafting and shared stashes beyond the completed item-shop system.
- [x] Clothing stores/barbers/outfit slots beyond the first appearance editor,
      including category enforcement and clothing-only share codes.
- [ ] Drugs/black-market loops.
- [ ] Police MDT/jail/evidence.
- [ ] EMS hospitals/beds/billing.

## Useful Next Milestones

1. Production hardening pass:
   profile library, smoke tests, validation, logging, and data migration metadata.
2. Inventory economy pass:
   shop selling/restocking, drops, stashes, trunks/gloveboxes, and crafting.
3. Vehicle pass:
   finish catalog templates, impound/depot, keys/locks, fuel/repair, persistent
   parking, and trunk inventories.
4. Job pass:
   map duty prompts, police/EMS/mechanic/taxi loops, dispatch/reports, and grade
   permissions.
5. World pass:
   weather polish, blackout light coverage, map-specific configuration, and place validation.

## Design Notes

- Roblox `Player.UserId` replaces FiveM license identifiers.
- One DataStore account profile holds all characters for a Roblox account.
- Server owns persistent gameplay data. Clients display data and send requests.
- Roblox vehicle and weapon assets must be real Studio templates; FiveM hashes and
  GTA natives do not map directly.
- Rojo-managed Studio objects should be edited in this workspace, not directly in
  Studio.
