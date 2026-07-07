# qb-core Roblox Port

This is a Rojo project for a Roblox/Luau port of the core QBCore flow:

- Account profile loading with DataStore-backed session locking.
- Character select, create, delete, and spawn.
- Persistence for money, job, crew, charinfo, position, and metadata.
- Client-side QBCore player data cache.
- Basic QBCore-style HUD for health, armor, hunger, and thirst.
- Death screen with timer-based self-respawn.
- Toast notification UI for `Player:Notify`.
- Server-authoritative hunger/thirst decay.
- Basic player inventory, five-slot hotbar, and native admin menu.
- Per-character appearance editor backed by saved HumanoidDescriptions.
- TextChatService slash commands for player/admin flows.
- Inventory-backed weapon Tool equip flow with ammo item consumption.
- First-pass vehicle registry and admin/command spawning from Roblox templates.
- QBMenu-style client menu, emotes menu, and proximity stage music controls.
- Synced Roblox-native weather with clouds/fog/rain/thunder/snow presets and blackout.

See [TODO.md](TODO.md) for the systems that are intentionally still missing.

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
      PlayerClass.lua      -- player money/job/crew/metadata methods
      AdminService.lua     -- permission-checked admin menu context/actions
      CommandService.lua   -- TextChatService command registry
      Commands.lua         -- default player/admin slash commands
      AppearanceService.lua -- saved HumanoidDescription appearance backend
      MedicalService.lua   -- death, respawn, armor, and medical item handlers
      InventoryService.lua -- player inventory and useable item helpers
      TimeSyncService.lua  -- day/night clock, /time and /freezetime commands
      WeaponService.lua    -- inventory-backed Roblox Tool equip flow
      VehicleService.lua   -- vehicle template spawn/delete helpers
      WeatherService.lua   -- synced weather cycling and tagged-light blackout
      StageMusicService.lua -- proximity speaker playback and Creator Store search
  StarterPlayer/StarterPlayerScripts/
    QBCoreClient.client.lua -- character select/create/delete UI
    QBAppearance.client.lua -- per-character avatar appearance editor
    QBAdmin.client.lua      -- native admin menu
    QBAmbulance.client.lua  -- death screen and self-respawn UI
    QBEmotes.client.lua     -- emote menu
    QBHUD.client.lua        -- health, armor, hunger, thirst HUD
    QBInventory.client.lua  -- player inventory and hotbar
    QBMenu.client.lua       -- reusable QBCore-style menu
    QBNotify.client.lua     -- toast notifications
    QBStageMusic.client.lua -- stage speaker music menu
    QBTimeCycle.client.lua  -- time-of-day visual grading
    QBWeather.client.lua    -- local precipitation and lightning visuals
    QBWeaponAmmo.client.lua -- local ammo/reload affordances
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

## Extending It

- Add real jobs/crews by expanding `QBShared/Jobs.lua` and `QBShared/Crews.lua`.
- Grant staff ranks by adding Roblox UserIds under `Config.Server.Permissions` (mod/admin/god); the game owner and Studio playtests are god automatically.
- Show a toast from server code with `playerObj:Notify("Message", "success", 4000)`.
- Extend inventory with shops, stashes, drops, vehicles, tools/weapons, and crafting.
- Extend the admin menu with reports, chat moderation, leaderboard, and deeper developer tools.
- Extend the first-pass vehicle spawner into persistent ownership, garages, keys, fuel, and trunks.
- Polish weather with custom precipitation textures, thunder audio, puddles, shelter checks, and map-specific blackout tags.
- Add paychecks and richer job/crew loops as separate systems.

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
