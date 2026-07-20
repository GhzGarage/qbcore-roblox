# qb-core Roblox Port

This is a Rojo project for a Roblox/Luau port of the core QBCore flow:

- Account profile loading with DataStore-backed session locking.
- Character select/create/delete plus QBSpawn-style location selection.
- Persistence for money, banking statements, player-shared and organization accounts, queued transfers, owned vehicles, job, crew, charinfo, position, and metadata.
- Client-side QBCore player data cache.
- Basic QBCore-style HUD for health, armor, hunger, and thirst.
- Native fixed-zoom rotating minimap with short-range and perimeter-clamped blips.
- Death screen with timer-based self-respawn.
- Toast notification UI for `Player:Notify`.
- Shared QBCore-style proximity prompt UI for keyboard, gamepad, and touch.
- Server-authoritative hunger/thirst decay.
- Player inventory, five-slot hotbar, two-pane external inventory UI, item shops, and native admin menu with a live loaded-character economy leaderboard.
- Proximity-prompt City Hall with public job selection and instant cash purchases for eligible identity/license items.
- QBAmbulance hospital POIs with patient check-in, staffed-EMS routing, timed bed treatment and billing, duty toggles, and grade-authorized ambulance retrieval.
- QBPoliceJob station POIs with duty, armory, personal lockers, trash, fingerprinting, evidence drawers, grade-authorized fleet retrieval, impound, and air-support points.
- Per-character appearance editor plus categorized clothing/barber shops, saved outfits, and clothing-only share codes.
- TextChatService slash commands for player/admin flows.
- Inventory-backed weapon Tool equip flow with ammo item consumption.
- Vehicle registry plus admin/command/dealership spawning from Roblox templates.
- Free-use dealership with showroom displays, test drives, ownership, and financing support.
- Public garages with persistent storage state, condition values, and safe retrieval.
- QBMenu-style client menu, emotes menu, and proximity stage music controls.
- Synced Roblox-native weather with clouds/fog/rain/thunder/snow presets and blackout.
- Proximity-prompt personal, player-shared, job, and crew banking with cards, PIN-gated ATMs, queued citizen transfers, and statements.
- Standalone job/crew management with rosters, nearby hiring, grades, removal, and offline queues.
- Inventory-opened StudOS smartphone with Roblox-filtered messaging, eligible voice calls, StudSpace social posts, and native captures.
- Instanced starter apartments with doorbells, visitors, wardrobes, logout points, and persistent personal stashes.
- Centralized UI theming and resolution scaling profiles for Roblox-native interfaces.

See [TODO.md](TODO.md) for the systems that are intentionally still missing.

## Reference Island Map

The repository includes a three-stage Roblox Studio generator based on
`reference_topdown.png`. It builds the terrain and districts, the traced road
network, and a rerunnable landmark/detail layer containing the airport, port,
farms, golf course, city façades, vegetation, and streetlights.

See [MAP_GENERATION.md](MAP_GENERATION.md) for the exact generation order and
Studio workflow.

## Layout

```text
src/
  ReplicatedStorage/
    QBShared/          -- Config, Jobs, Crews, Items, Vehicles, Weather, StageMusic, shared main module
    QBRemoteNames.lua  -- remote names used by both server and client
    QBRemotes.lua      -- creates/waits for RemoteEvents and RemoteFunctions
    QBCoreClient.lua   -- client PlayerData cache and BindableEvent signals
    QBUITheme.lua      -- centralized color/tone palettes and UI tokens
    QBUIScale.lua      -- centralized viewport scaling profiles/helpers
  ServerScriptService/
    QBCore/
      Main.server.lua      -- server entrypoint and remote wiring
      Access.lua           -- whitelist, bans, graded permissions
      ProfileStore.lua     -- simplified session-locked DataStore wrapper
      PlayerService.lua    -- account, character, spawn, save, status loop
      SpawnService.lua     -- post-multicharacter spawn selection and validation
      ApartmentService.lua -- apartment shells, prompts, doorbells, visitors, and stashes
      PaycheckService.lua  -- configurable job-grade paycheck loop
      BankingService.lua   -- personal/shared/organization banking, cards, ATMs, and transfer queue
      PlayerClass.lua      -- player money/job/crew/metadata methods
      AdminService.lua     -- permission-checked admin menu context/actions
      CommandService.lua   -- TextChatService command registry
      Commands.lua         -- default player/admin slash commands
      AppearanceService.lua -- appearance, categorized shops, saved outfits, and share codes
      MedicalService.lua   -- death, respawn, armor, medical items, hospitals, and EMS job POIs
      PoliceService.lua    -- police station POIs, secure containers, fleet, fingerprints, and impound
      InventoryService.lua -- player inventory, external-provider contract, and useable item helpers
      ShopService.lua      -- proximity shops, filtered catalogs, stock, and purchases
      TimeSyncService.lua  -- day/night clock, /time and /freezetime commands
      WeaponService.lua    -- inventory-backed Roblox Tool equip flow
      VehicleService.lua   -- vehicle template spawn/delete helpers
      VehicleShopService.lua -- showroom, purchases, ownership, financing, test drives
      GarageService.lua    -- public garage deposit/retrieval and persistent state
      ManagementService.lua -- job/crew rosters, hiring, grades, and offline queues
      WeatherService.lua   -- synced weather cycling and tagged-light blackout
      StageMusicService.lua -- proximity speaker playback and Creator Store search
      PhoneService.lua    -- item access, private text channels, voice-call routing, and phone profile state
  StarterPlayer/StarterPlayerScripts/
    QBCoreClient.client.lua -- character select/create/delete UI
    QBAppearance.client.lua -- appearance/shop editor and outfit manager
    QBBanking.client.lua    -- personal/shared/organization accounts, ATM, and history UI
    QBVehicleShop.client.lua -- dealership catalog, owned vehicles, and finance UI
    QBGarage.client.lua     -- public garage vehicle list and storage UI
    QBManagement.client.lua -- standalone job/crew boss management UI
    QBAdmin.client.lua      -- native admin menu
    QBSpawn.client.lua      -- last/public/apartment spawn selector
    QBApartments.client.lua -- apartment entrance, doorbell, and stash panels
    QBAmbulance.client.lua  -- death/respawn UI plus hospital check-in and EMS garage menus
    QBPoliceJob.client.lua  -- police fleet and fingerprint result menus
    QBEmotes.client.lua     -- emote menu
    QBHUD.client.lua        -- identity, money, status, and ammo HUD
    QBMinimap.client.lua    -- starts the fixed-zoom native minimap
    QBInventory.client.lua  -- player/external inventory panes, shops, and hotbar
    QBMenu.client.lua       -- reusable QBCore-style menu
    QBNotify.client.lua     -- toast notifications
    QBPrompt.client.lua     -- shared custom proximity prompt UI
    QBStageMusic.client.lua -- stage speaker music menu
    QBTimeCycle.client.lua  -- time-of-day visual grading
    QBWeather.client.lua    -- local precipitation and lightning visuals
    QBWeaponAmmo.client.lua -- local ammo/reload affordances
    QBPhone.client.lua    -- StudOS phone, messages, calls, camera/photos, StudSpace, tools, and settings
```

Naming convention: `<Name>.server.lua` becomes a Script, `<Name>.client.lua` a
LocalScript, plain `<Name>.lua` a ModuleScript -- the suffix is how Rojo picks the
class, so it can never be dropped. Single-file client resources sit directly in
`StarterPlayerScripts/` as `<Name>.client.lua`; multi-file resources get a folder
with a `Main.server.lua`/`Main.client.lua` entrypoint and sibling ModuleScripts.

## Rojo Workflow

Use `serve`, not `build`, for normal Studio development:

```powershell
.\serve-rojo.bat
```

Then connect the Roblox Studio Rojo plugin to:

```text
localhost:34872
```

Keep the terminal open while you work. File edits in this workspace will stream into Studio.

Use `rojo build` only when you want a standalone place file:

```powershell
rojo build default.project.json --output qbcore-roblox.rbxlx
```

## Studio Setup

DataStores do not work in Studio Play mode by default. Enable:

```text
Game Settings -> Security -> Enable Studio Access to API Services
```

## Smartphone Setup

New characters receive one unique `phone` in starter inventory slot 3. Existing
characters receive one on their next load if they have an empty inventory slot.
The migration is recorded once, so a deliberately lost phone is not recreated.
There is no dedicated phone key: click/use its inventory or hotbar slot to open StudOS.
Every server request checks that the character still owns the item.

Messaging and StudSpace posts use `TextChannel:SendAsync`, allowing Roblox to
filter delivery for each receiver. Private channels are created only after
`TextChatService:CanUsersDirectChatAsync` approves the two same-server players.

Calls are same-server Roblox voice calls. Configure the published experience in
Studio before testing them:

```text
Experience Settings -> Communication -> Enable Microphone
Experience Settings -> Communication -> Chat & Voice Groups APIs
VoiceChatService.UseAudioApi = Enabled
```

Agree to the Roblox Chat & Voice Groups terms when prompted. Group APIs can only
be exercised in Studio Team Test; a normal solo Play test will report that voice
group checks are unavailable. Both players must also be voice-enabled and in a
compatible Roblox communication group. The phone connects each eligible
`AudioDeviceInput` to an `AudioDeviceOutput` targeted only at the other caller.

The Camera app uses `CaptureService:TakeScreenshotCaptureAsync` with phone UI
excluded. Captures remain in the current session until the user taps a thumbnail
in Photos and accepts Roblox's native save-to-Captures prompt. This intentionally
does not pretend capture objects can be persisted in character DataStores.

StudOS keeps only feasible settings: Do Not Disturb and phone sounds. Device
frame colors are omitted because the phone is a native GUI rather than a
persistent physical case asset.

If Studio starts showing duplicate QBCore/QBShared objects:

1. Stop Play mode.
2. Disconnect the Rojo plugin.
3. Run `tools/clean-rojo-studio-objects.lua` in Studio's Command Bar.
4. Reconnect the Rojo plugin to `localhost:34872`.

Treat this workspace as the source of truth for Rojo-managed objects:

```text
ReplicatedStorage/QBShared
ReplicatedStorage/QBRemoteNames
ReplicatedStorage/QBRemotes
ReplicatedStorage/QBCoreClient
ReplicatedStorage/QBUITheme
ReplicatedStorage/QBUIScale
ServerScriptService/QBCore
StarterPlayer/StarterPlayerScripts/QBAppearance
StarterPlayer/StarterPlayerScripts/QBCoreClient
StarterPlayer/StarterPlayerScripts/QBAdmin
StarterPlayer/StarterPlayerScripts/QBAmbulance
StarterPlayer/StarterPlayerScripts/QBEmotes
StarterPlayer/StarterPlayerScripts/QBHUD
StarterPlayer/StarterPlayerScripts/QBInventory
StarterPlayer/StarterPlayerScripts/QBMenu
StarterPlayer/StarterPlayerScripts/QBNotify
StarterPlayer/StarterPlayerScripts/QBPrompt
StarterPlayer/StarterPlayerScripts/QBStageMusic
StarterPlayer/StarterPlayerScripts/QBTimeCycle
StarterPlayer/StarterPlayerScripts/QBWeather
StarterPlayer/StarterPlayerScripts/QBWeaponAmmo
```

In Studio, `ServerScriptService.QBCore` is a Folder whose entrypoint is the `Main`
Script inside it, and the `QB*` entries under StarterPlayerScripts are LocalScripts.
`ServerScriptService` is configured to preserve unknown children so imported Roblox
systems like `WeaponsSystem` can live next to the Rojo-managed `QBCore` folder.

## Tuning

Hunger and thirst are configured in `src/ReplicatedStorage/QBShared/Config.lua`:

```lua
Config.StatusInterval = 120
Config.StatusDecay = {
    Enabled = true,
    Hunger = 1,
    Thirst = 1,
}
```

The current defaults are slower and closer to live gameplay; lower
`StatusInterval` temporarily when you want the HUD to move quickly in Studio.

The minimap is configured in the same file. Import `ref_final/roads.png` through
Studio, then set `Image` to the resulting image asset ID. `StudsAcross` controls
the fixed zoom. A normal blip disappears beyond `displayRadius`; an
`alwaysShow = true` blip remains visible and clamps to the minimap perimeter.

```lua
Config.HUD.Minimap.Image = "rbxassetid://123456789"
Config.HUD.Minimap.StudsAcross = 1900
Config.HUD.Minimap.Blips = {
    {
        id = "hospital",
        position = Vector3.new(-249.08, 2.43, -1066.27),
        symbol = "+",
        alwaysShow = true,
    },
}
```

Client systems can also use `ReplicatedStorage.QBMinimap.AddBlip()`, or tag a
Part, Attachment, or Model with `QBMinimapBlip`. The minimap automatically hides
while the local player's `QBApartmentId` attribute is set; status, ammo, and the
rest of QBHUD stay visible. Other client systems can toggle it directly with
`QBMinimap.SetVisible(false)` or `QBMinimap.SetVisible(true)`. Tagged instances accept the
`MinimapAlwaysShow`, `MinimapDisplayRadius`, `MinimapColor`, `MinimapSymbol`,
`MinimapImage`, `MinimapSize`, `MinimapLabel`, and optional `MinimapId`
attributes.

Character slots are also configured there:

```lua
Config.Player.MaxCharacterSlots = 5
```

## UI Theming And Scaling

Roblox-native UI now shares centralized theme and scaling modules in
`ReplicatedStorage`:

- `QBUITheme.lua` controls palette families and reusable visual tokens.
- `QBUIScale.lua` controls resolution scaling profiles and viewport helpers.

Most large LocalScript UIs consume these modules directly. To reskin the
project, change palette values in `QBUITheme.Palettes`. To retune responsiveness,
adjust profile baselines and clamps in `QBUIScale.Profiles`.

Palette families:

- `Core`: baseline gameplay panel set.
- `Service`: wider service-style panels (banking/garage/management/shop/admin).
- `Compact`: compact panel set (spawn/apartments).
- `Utility`: HUD/prompt/menu/notify/minimap baseline set.

Scale profiles:

- `HUD`, `Panel`, `WidePanel`, `Dialog`, `CompactDialog`, `Phone`.

Recommended workflow for UI changes:

1. Adjust color/tone intent in `QBUITheme.lua`.
2. Adjust per-class screen scaling limits in `QBUIScale.lua`.
3. Verify in Studio at desktop and smaller viewport sizes.

Test lighting/spawn defaults are configured there too:

```lua
Config.World.Time.StartHour = 12
Config.World.CloudCover = 0.45
Config.Player.CharacterDefaults.position = { x = -175.00, y = 3.70, z = 333.57, ry = 358.6 }
```

Death screen respawn behavior is configured there as well:

```lua
Config.Medical.DeathScreen.RespawnDelay = 30
Config.Medical.Respawn.WipeInventory = false
Config.Medical.Respawn.UseConfiguredLocation = false
Config.Medical.Respawn.Location = { x = -175.00, y = 3.70, z = 333.57, ry = 358.6 }
```

Hospital and EMS POIs live under `Config.Medical.Hospital.Hospitals`. Each
hospital can define one or more `checkIn`, `duty`, and `vehicle` points, a
`vehicleSpawn`, grade-authorized vehicles, and treatment beds. The server
creates the corresponding proximity prompts and revalidates distance, job,
duty, grade, bed availability, and payment for every action.

```lua
Config.Medical.Hospital.BillCost = 2000
Config.Medical.Hospital.MinimalDoctors = 2
Config.Medical.Hospital.Hospitals[1].checkIn = { Vector3.new(-249.08, 2.43, -1066.27) }
```

Police POIs live under `Config.PoliceJob.Stations`. A station can independently
place `duty`, `armory`, `stash`, `trash`, `fingerprint`, `evidence`, `vehicle`,
`impound`, and `helicopter` points. The included `mission_row` development block
is near the current city-services test hub; move that one block when the final
police interior is ready. Personal lockers persist with the character, while
evidence and trash containers are shared for the server session. All container,
armory, fleet, fingerprint, and impound actions revalidate police duty and distance.

```lua
Config.PoliceJob.Stations[1].duty = { Vector3.new(-255, 3.7, 315.57) }
Config.PoliceJob.Stations[1].evidence[1].drawer = 1
Config.PoliceJob.Stations[1].authorizedVehicles = {
	{ name = "police", label = "Police Cruiser", minGrade = 0 },
}
```

Weather behavior is configured there too:

```lua
Config.Weather.StartWeather = "CLEAR"
Config.Weather.Dynamic = true
Config.Weather.TransitionSeconds = 45
Config.Weather.BlackoutLightTags = { "QBBlackoutLight", "StreetLight" }
```

Admins can use `/weather`, `/freezeweather`, and `/blackout`; the native admin
menu also exposes these controls on the Environment tab.

Job-grade paychecks and the `/duty` toggle use the money configuration:

```lua
Config.Money.PayCheckEnabled = true
Config.Money.PayCheckTimeOut = 10 * 60
Config.Money.PayCheckOnDutyOnly = true
Config.Money.PayCheckSociety = false
```

`BankingService` is registered as the society-funds provider during startup. When
`PayCheckSociety` is enabled, the matching job account is debited atomically before
each paycheck; insufficient society funds cause that paycheck to be skipped.

Bank locations and transaction limits are configured in the same file. Each
location becomes an invisible anchored part with a native `ProximityPrompt`:

```lua
Config.Banking.PromptDistance = 10
Config.Banking.ActionDistance = 14
Config.Banking.MaxTransactionAmount = 1000000
Config.Banking.MaxStatements = 50
Config.Banking.CardPrice = 50
Config.Banking.UseDailyWithdrawalLimit = true
Config.Banking.DailyWithdrawalLimit = 5000
Config.Banking.Society = { Enabled = true, DefaultBalance = 0, StartingBalances = {} }
Config.Banking.SharedAccounts = { Enabled = true, MaxOwned = 2, MaxMembers = 10 }
Config.Banking.Locations = {
    { id = "test_bank", label = "QBCore Bank", position = Vector3.new(6.21, 3.45, -1492.88) },
}
Config.Banking.ATMLocations = {
    { id = "test_atm", label = "QBCore ATM", position = Vector3.new(26.21, 3.45, -1492.88) },
}
```

Players can open shared accounts, add or remove members by citizen ID, rename accounts
they own, and close empty accounts. Boss grades can deposit, withdraw, and transfer
from their job or crew organization account. All account money controls live in the
banking UI; the management panel does not expose balances or transactions.
Transfers use citizen IDs; online recipients are credited immediately, while
offline recipients receive a durable, deduplicated transfer on their next login.
Cards are issued from the bank UI and are required with their PIN at ATM prompts.

The temporary vehicle dealership is configured under `Config.VehicleShop`.
Every shared vehicle currently defaults to `$0`; `taxi` and `police` are excluded
again on the server even if a client submits their names directly.

```lua
Config.VehicleShop.TestDriveSeconds = 60
Config.VehicleShop.ShowroomSpots = {
    { position = Vector3.new(-146.919, 0.997, -36.539), heading = -45 },
    -- three more configured showroom positions
}
Config.VehicleShop.FinanceSpot.position = Vector3.new(-143.852, 4.707, -115.063)
Config.VehicleShop.VehicleSpawn = {
    position = Vector3.new(-208.801, 2.524, -146.146),
    heading = 180,
}
```

Showroom and finance anchors use native `ProximityPrompt`s. Purchases are saved
on the selected character before release, test drives expire automatically, and
the shared exit refuses to spawn while another runtime vehicle blocks it.

Public garages use the same prompt and owned-vehicle records. Both placeholder
locations currently use the origin and should be replaced before a real playtest:

```lua
Config.Garages.DefaultGarage = "garage_1"
Config.Garages.AutoRespawn = true
Config.Garages.SharedGarages = false
Config.Garages.Locations = {
    {
        id = "garage_1",
        takeVehicle = Vector3.new(0, 0, 0),
        spawnPoints = { { position = Vector3.new(0, 0, 0), heading = 0 } },
    },
    -- garage_2 is also at 0, 0, 0 until replaced
}
```

Storing validates the runtime ownership ID, saves fuel/engine/body condition and
garage state, then removes the vehicle. Retrieval saves the out state and refuses
blocked spawn points. With `AutoRespawn`, out vehicles return to their last or
default garage when the owner disconnects.

Job and crew bosses use the standalone management panel from invisible prompt
anchors under `Config.Management`. The two starter locations overlap at the origin
and should be moved to the real headquarters before playtesting:

```lua
Config.Management.Locations = {
    { id = "job_management_1", type = "job", position = Vector3.new(0, 0, 0) },
    { id = "crew_management_1", type = "crew", position = Vector3.new(0, 0, 0) },
}
```

Every request revalidates proximity, the current organization, and boss grade on
the server. Bosses can view indexed online/offline rosters, hire nearby loaded
characters, assign grades no higher than their own, and remove members. Job and crew
accounts are accessed exclusively through banking. Session-locked offline profiles are
never edited unsafely: changes are queued and applied on that character's next load.
Existing characters enter the roster index the first time they load after this
system is installed. The Wardrobe shortcut opens the clothing-only saved-outfit
manager after revalidating the boss prompt; shared stashes still depend on the
future container system.

Clothing interactions are configured under `Config.Clothing`. The included
clothing store, accessory store, barber, and outfit wardrobe are intentionally
stacked at the origin until real storefront positions are supplied:

```lua
Config.Appearance.AllowFullEditorCommand = false
Config.Clothing.MaxOutfits = 20
Config.Clothing.RequireOwnershipForSharedOutfits = false
Config.Clothing.Shops = {
    {
        id = "clothing_shop_1",
        position = Vector3.new(0, 0, 0),
        categories = { "Shirts", "Pants", "Jackets", "Shoes" },
        allowOutfits = true,
    },
    -- accessory, barber, and outfit-only locations are also configured
}
```

Each prompt opens the same appearance UI with only its configured tabs. The
server independently enforces those categories on previews, saves, and outfit
application. Saving an outfit stores only classic/layered clothing and wearable
accessories; hair, face, makeup/future identity fields, body parts, scales, and
skin color never enter a share code. Deleting an outfit or character revokes its
code. Set `RequireOwnershipForSharedOutfits` to `true` if recipients should also
own every catalog asset.

## Spawn Selection And Apartments

Selecting a character now closes multicharacter and opens `QBSpawn`. Returning
characters can choose their last outdoor location, any `Config.Spawn.Locations`
entry, or their apartment. With `Config.Apartments.Starting = true`, a fresh
character chooses one of the configured apartment buildings and is assigned a
persistent unit before the first appearance editor opens.

The selection paths can be disabled independently:

```lua
Config.Spawn.Enabled = true -- master QBSpawn UI switch
Config.Spawn.AllowSelectionForExistingCharacters = false -- auto-resume last location
Config.Spawn.DefaultSpawn = {
    position = Vector3.new(-175, 3.7, 333.57),
    heading = 358.6,
}
Config.Apartments.Starting = false -- new characters skip QBSpawn and use DefaultSpawn
```

`AllowSelectionForExistingCharacters = false` affects returning characters only;
starter-apartment selection can remain enabled for fresh characters. Turning
`Starting` off makes fresh characters load directly at `DefaultSpawn` after their
registration succeeds. Setting `Config.Spawn.Enabled = false` is the master bypass:
returning characters use their last location and fresh characters use `DefaultSpawn`.

No Roblox `Character` exists during multicharacter or QBSpawn. The selected
QBCore record remains in a pending session and is excluded from active-character
lists, paychecks, status decay, transfers, and gameplay services. `LoadCharacter()`
runs only after the server validates the player's explicit spawn choice; only then
are player data and `PlayerLoaded` sent to gameplay clients.

Apartment entrances use invisible ProximityPrompt anchors. The included starter
building is a placeholder at `0, 0, 0`. Replace its `position` and `heading` under
`Config.Apartments.Buildings`; public spawn points are configured separately under
`Config.Spawn.Locations`.

Until a real interior is installed, `ApartmentService` creates a simple open-plan
blockout. To replace it, insert this hierarchy in Studio:

```text
ServerStorage
  QBApartmentInteriors
    StarterApartment (Model)
      Spawn     (BasePart)
      Exit      (BasePart)
      Stash     (BasePart)
      Wardrobe  (BasePart)
      Logout    (BasePart)
      ...your visible interior geometry...
```

Place the five marker parts exactly where players and prompts belong. They may be
fully transparent and non-colliding. Keep the model near its own origin; the server
clones and pivots it into an allocated distant grid cell. If a marker is missing,
that interaction is omitted (`Spawn` falls back to `Exit`, then the model pivot).
The model name must match the building's `interior` field. You can add more building
entries and reuse the same model.

Every unit is server-authoritative and exists only while occupied. Doorbell requests
expire, visitors must still be waiting at the correct entrance, and guests cannot use
the resident's stash, wardrobe, or logout point. When the resident leaves or
disconnects, guests are returned to the exterior. Interior grid coordinates are never
written as a character's last location.

## Item Shops

`Config.Shops.Products` defines reusable catalogs and `Config.Shops.Locations`
places proximity-prompt counters. A product supports `price`, `amount`, `info`,
`requiredJob`, `requiredCrew`, `requiredGrade`, and `requiredLicense`; locations can
apply the same job/crew/item restrictions to the whole store. Stock is authoritative
for the current server session and resets on restart because delivery/restocking is
intentionally not part of this port.

Opening a shop keeps the player inventory on the left and adds the shop on the
right. Select a product, choose a quantity, and buy it. The server rechecks distance,
access, stock, weight/slot capacity, and payment before changing money or inventory.
Normal `Tab`/Bag access remains a single pane. Future stashes, trunks, and gloveboxes
can register an external provider through `InventoryService.RegisterExternalProvider`
and reuse the same snapshot/action path.

## City Hall

`Config.CityHall.Locations` places City Hall prompts, `AvailableJobs` controls the
public job list, and `Documents` controls document prices and license eligibility.
Police, ambulance, and mechanic are denied independently through `RestrictedJobs`.
The server rechecks proximity and eligibility for every request, takes cash only
after confirming inventory capacity, and immediately adds character-specific item
metadata for the issued document.

## Extending It

- Add real jobs/crews by expanding `QBShared/Jobs.lua` and `QBShared/Crews.lua`.
- Grant staff ranks by adding Roblox UserIds under `Config.Server.Permissions` (mod/admin/god); the game owner and Studio playtests are god automatically.
- Show a toast from server code with `playerObj:Notify("Message", "success", 4000)`.
- Extend inventory with stashes, drops, vehicle containers, richer shop catalogs, and crafting.
- Extend the admin menu with reports, chat moderation, and deeper developer tools.
- Extend owned vehicles with impound/depot, job/house garages, keys, real fuel/damage integrations, and trunks.
- Polish weather with custom precipitation textures, thunder audio, puddles, shelter checks, and map-specific blackout tags.
- Expand the `/duty` toggle into map prompts, blips, permissions, and richer job/crew loops.

## Weapon Tool Setup

Weapon item data lives in `QBShared/Items.lua`; the actual Roblox Tool templates
should be stored in `ServerStorage/QBWeaponTools`.

Preferred setup in Studio:

```text
ServerScriptService
  WeaponsSystem
ServerStorage
  QBWeaponTools
    Pistol
```

Each weapon item can override the endorsed Tool template's direct `Configuration`
values with `weapon.config`:

```lua
weapon = {
    toolName = "Pistol",
    config = {
        AmmoCapacity = 12,
        FireMode = "Semiautomatic",
        HitDamage = 24,
        MaxSpread = 2,
        ShotCooldown = 0.18,
    },
}
```

QBCore applies those values to the cloned Tool before equipping it. Existing
Studio `ValueBase` objects are reused, missing number/string/boolean values are
created, and omitted values keep the template's current settings. You can also set
other weapon-kit values such as `GravityFactor`, `MuzzleFlashSize0`,
`MuzzleFlashSize1`, `RecoilDecay`, `RecoilMin`, `RecoilMax`, `TotalRecoilMax`,
`ShotEffect`, or `CasingEffect`.

When adding the endorsed Roblox pistol from Toolbox, click **No** on the StarterPack
prompt. That imports it as a world pickup, but only temporarily: move the `Pistol`
Tool into `ServerStorage/QBWeaponTools`, and move the imported `WeaponsSystem` folder
into `ServerScriptService`.

If the free Roblox pistol lands in `Workspace` or `StarterPack`, the server will try
to move a loose `Pistol` Tool into `ServerStorage/QBWeaponTools` at runtime. If the
asset brings a loose `WeaponsSystem` folder, the server will move it to
`ServerScriptService` when no unified system folder exists yet. Equipped QBCore
weapon clones set `CanBeDropped = false`, so players should not be able to drop a gun
pickup onto the map.

If `QBWeaponTools` is not visible in Explorer yet, either create a `Folder` named
`QBWeaponTools` under `ServerStorage` manually, reconnect Rojo, or run
`tools/setup-weapons-kit.lua` in Studio's Command Bar after inserting the pistol.

If `WeaponsSystem/Libraries/ShoulderCamera` spams a read-only `C0` error in Studio,
stop Play mode and run `tools/patch-weapons-shoulder-camera.lua` in Studio's Command
Bar. It disables only the root-joint visual fix that causes the spam.

If one player equipping a weapon makes every player see the weapon crosshair, stop
Play mode and run `tools/patch-weapons-local-crosshair.lua` in Studio's Command Bar.
It keeps remote players' equipped weapons from becoming the local client's active
weapon/camera state.

For Studio testing, give the item with:

```text
/giveitem <userId-or-name> weapon_pistol 1
```
