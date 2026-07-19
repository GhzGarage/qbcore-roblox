-- Single source of truth for remote names, required by both the server and client.

return {
	RemoteEvents = {
		"PlayerDataUpdated", -- server -> client: (key, value) or ('all', PlayerData)
		"PlayerLoaded", -- server -> client: () character has entered the world after spawn selection
		"Notify", -- server -> client: (text, notifyType, length)
		"OpenInventory", -- server -> client: (access) open player inventory with an external pane
		"CloseInventory", -- client -> server: (access) release the active external inventory
		"OpenAppearanceEditor", -- server -> client: (serializedAppearance, isNewCharacter, editorContext)
		"RequestAppearanceEditor", -- client -> server: () ask for full editor when config permits
		"PreviewAppearance", -- client -> server: (serializedAppearance) live try-on, applied to the character
		"CancelAppearanceEdit", -- client -> server: () revert the character to the last saved look
		"OpenAdminMenu", -- server -> client: () open the native admin panel
		"OpenBank", -- server -> client: ({ mode, locationId }) open the bank/ATM panel
		"OpenVehicleShop", -- server -> client: ({ mode, locationId, vehicleName? })
		"OpenGarage", -- server -> client: ({ garageId }) open a public garage
		"OpenManagement", -- server -> client: ({ locationId }) open boss/crew management
		"OpenEmoteMenu", -- server -> client: () open the native emote menu
		"OpenStageMusicMenu", -- server -> client: (station snapshot) open the stage music menu
		"OpenPhone", -- server -> client: (phone snapshot) open from the inventory phone item
		"OpenSpawnSelector", -- server -> client: (spawn snapshot) choose where the selected character enters
		"OpenApartment", -- server -> client: (view, payload) apartment menu, doorbell, or stash UI
		"OpenCityHall", -- server -> client: ({ locationId }) open city services
		"OpenHospital", -- server -> client: ({ view, access, ... }) open hospital check-in/job menus
		"OpenPoliceJob", -- server -> client: ({ view, access, ... }) open police POI menus/results
		"PhonePush", -- server -> client: (action, payload) incoming calls and phone state
		"StageMusicControl", -- client -> server: ({ action, stationId, trackId }) control nearby stage music
		"WeatherStateUpdated", -- server -> client: (weather snapshot) authoritative weather/blackout state
		"JobRouteUpdated", -- server -> client: (objective snapshot or nil) route-job waypoint/progress state
	},
	RemoteFunctions = {
		"GetCharacters", -- client -> server: () -> array of {citizenId, cid, firstname, lastname}
		"SelectCharacter", -- client -> server: (citizenId) -> boolean, errorMessage?
		"CreateCharacter", -- client -> server: (firstname, lastname) -> citizenId, errorMessage?
		"DeleteCharacter", -- client -> server: (citizenId) -> boolean, errorMessage?
		"SaveAppearance", -- client -> server: (serializedAppearance) -> boolean, errorMessage?
		"OutfitAction", -- client -> server: (action, payload) -> boolean, resultOrError
		"GetInventory", -- client -> server: (access?) -> player snapshot with optional external inventory
		"InventoryAction", -- client -> server: (action, payload) -> boolean, snapshotOrError
		"MoveInventoryItem", -- client -> server: (fromSlot, toSlot) -> boolean, errorMessage?
		"GiveInventoryItem", -- client -> server: (slot) -> boolean, errorMessage?
		"UseInventorySlot", -- client -> server: (slot) -> boolean, errorMessage?
		"RequestRespawn", -- client -> server: () -> boolean, errorMessage?
		"GetAdminContext", -- client -> server: () -> admin menu snapshot, permission checked
		"AdminAction", -- client -> server: (action, payload) -> boolean, resultOrError
		"GetBanking", -- client -> server: (access) -> banking snapshot, errorMessage?
		"BankingAction", -- client -> server: (action, payloadWithAccess) -> boolean, snapshotOrError
		"GetVehicleShop", -- client -> server: (access) -> catalog/owned snapshot, errorMessage?
		"VehicleShopAction", -- client -> server: (action, payloadWithAccess) -> boolean, resultOrError
		"GetGarage", -- client -> server: (access) -> garage/vehicle snapshot, errorMessage?
		"GarageAction", -- client -> server: (action, payloadWithAccess) -> boolean, resultOrError
		"GetManagement", -- client -> server: (access) -> authorized organization snapshot
		"ManagementAction", -- client -> server: (action, payloadWithAccess) -> boolean, resultOrError
		"OpenManagementWardrobe", -- client -> server: (management access) -> boolean, errorMessage?
		"GetPhoneSnapshot", -- client -> server: () -> phone profile and online contacts
		"PhoneRequest", -- client -> server: (action, payload) -> boolean, resultOrError
		"SelectSpawn", -- client -> server: (choice id) -> boolean, errorMessage?
		"ApartmentAction", -- client -> server: (action, payload) -> boolean, resultOrError
		"GetCityHall", -- client -> server: (access) -> city hall services snapshot, errorMessage?
		"CityHallAction", -- client -> server: (action, payloadWithAccess) -> boolean, resultOrError
		"HospitalAction", -- client -> server: (action, payloadWithAccess) -> boolean, resultOrError
		"PoliceAction", -- client -> server: (action, payloadWithAccess) -> boolean, resultOrError
	},
}
