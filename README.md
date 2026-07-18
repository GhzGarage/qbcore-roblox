# qb-core Roblox Port

This is a Rojo project for a Roblox/Luau port of the core QBCore flow:

- Account profile loading with DataStore-backed session locking.
- Character select, create, delete, and spawn.
- Persistence for money, banking statements, society accounts, queued transfers, owned vehicles, job, crew, charinfo, position, and metadata.
- Client-side QBCore player data cache.
- Basic QBCore-style HUD for health, armor, hunger, and thirst.
- Death screen with timer-based self-respawn.
- Toast notification UI for `Player:Notify`.
- Server-authoritative hunger/thirst decay.
- Player inventory, five-slot hotbar, two-pane external inventory UI, item shops, and native admin menu.
- Per-character appearance editor plus categorized clothing/barber shops, saved outfits, and clothing-only share codes.
- TextChatService slash commands for player/admin flows.
- Inventory-backed weapon Tool equip flow with ammo item consumption.
- Vehicle registry plus admin/command/dealership spawning from Roblox templates.
- Free-use dealership with showroom displays, test drives, ownership, and financing support.
- Public garages with persistent storage state, condition values, and safe retrieval.
- QBMenu-style client menu, emotes menu, and proximity stage music controls.
- Synced Roblox-native weather with clouds/fog/rain/thunder/snow presets and blackout.
- Proximity-prompt personal/society banking with cards, PIN-gated ATMs, queued citizen transfers, and statements.
- Standalone job/crew management with rosters, nearby hiring, grades, removal, offline queues, and shared funds.
- Inventory-opened StudOS smartphone with Roblox-filtered messaging, eligible voice calls, StudSpace social posts, and native captures.

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
  ServerScriptService/
    QBCore/
      Main.server.lua      -- server entrypoint and remote wiring
      Access.lua           -- whitelist, bans, graded permissions
      ProfileStore.lua     -- simplified session-locked DataStore wrapper
      PlayerService.lua    -- account, character, spawn, save, status loop
      PaycheckService.lua  -- configurable job-grade paycheck loop
      BankingService.lua   -- personal/society banking, cards, ATMs, and transfer queue
      PlayerClass.lua      -- player money/job/crew/metadata methods
      AdminService.lua     -- permission-checked admin menu context/actions
      CommandService.lua   -- TextChatService command registry
      Commands.lua         -- default player/admin slash commands
      AppearanceService.lua -- appearance, categorized shops, saved outfits, and share codes
      MedicalService.lua   -- death, respawn, armor, and medical item handlers
      InventoryService.lua -- player inventory, external-provider contract, and useable item helpers
      ShopService.lua      -- proximity shops, filtered catalogs, stock, and purchases
      TimeSyncService.lua  -- day/night clock, /time and /freezetime commands
      WeaponService.lua    -- inventory-backed Roblox Tool equip flow
      VehicleService.lua   -- vehicle template spawn/delete helpers
      VehicleShopService.lua -- showroom, purchases, ownership, financing, test drives
      GarageService.lua    -- public garage deposit/retrieval and persistent state
      ManagementService.lua -- job/crew rosters, hiring, grades, and shared funds
      WeatherService.lua   -- synced weather cycling and tagged-light blackout
      StageMusicService.lua -- proximity speaker playback and Creator Store search
      PhoneService.lua    -- item access, private text channels, voice-call routing, and phone profile state
  StarterPlayer/StarterPlayerScripts/
    QBCoreClient.client.lua -- character select/create/delete UI
    QBAppearance.client.lua -- appearance/shop editor and outfit manager
    QBBanking.client.lua    -- personal/society account, ATM, and history UI
    QBVehicleShop.client.lua -- dealership catalog, owned vehicles, and finance UI
    QBGarage.client.lua     -- public garage vehicle list and storage UI
    QBManagement.client.lua -- standalone job/crew boss management UI
    QBAdmin.client.lua      -- native admin menu
    QBAmbulance.client.lua  -- death screen and self-respawn UI
    QBEmotes.client.lua     -- emote menu
    QBHUD.client.lua        -- health, armor, hunger, thirst HUD
    QBInventory.client.lua  -- player/external inventory panes, shops, and hotbar
    QBMenu.client.lua       -- reusable QBCore-style menu
    QBNotify.client.lua     -- toast notifications
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

Character slots are also configured there:

```lua
Config.Player.MaxCharacterSlots = 5
```

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
Config.Banking.Locations = {
    { id = "test_bank", label = "QBCore Bank", position = Vector3.new(6.21, 3.45, -1492.88) },
}
Config.Banking.ATMLocations = {
    { id = "test_atm", label = "QBCore ATM", position = Vector3.new(26.21, 3.45, -1492.88) },
}
```

Boss grades can deposit, withdraw, and transfer from their job's society account.
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
characters, assign grades no higher than their own, remove members, and deposit or
withdraw cash from job or crew shared accounts. Session-locked offline profiles are
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

## Extending It

- Add real jobs/crews by expanding `QBShared/Jobs.lua` and `QBShared/Crews.lua`.
- Grant staff ranks by adding Roblox UserIds under `Config.Server.Permissions` (mod/admin/god); the game owner and Studio playtests are god automatically.
- Show a toast from server code with `playerObj:Notify("Message", "success", 4000)`.
- Extend inventory with stashes, drops, vehicle containers, richer shop catalogs, and crafting.
- Extend the admin menu with reports, chat moderation, leaderboard, and deeper developer tools.
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
