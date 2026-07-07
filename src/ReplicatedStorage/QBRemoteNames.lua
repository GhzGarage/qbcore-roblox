-- Single source of truth for remote names, required by both the server and client.

return {
	RemoteEvents = {
		"PlayerDataUpdated", -- server -> client: (key, value) or ('all', PlayerData)
		"PlayerLoaded", -- server -> client: ()
		"Notify", -- server -> client: (text, notifyType, length)
		"OpenAppearanceEditor", -- server -> client: (serializedAppearance, isNewCharacter)
		"RequestAppearanceEditor", -- client -> server: () ask the server to reopen the editor
		"PreviewAppearance", -- client -> server: (serializedAppearance) live try-on, applied to the character
		"CancelAppearanceEdit", -- client -> server: () revert the character to the last saved look
		"OpenAdminMenu", -- server -> client: () open the native admin panel
		"OpenEmoteMenu", -- server -> client: () open the native emote menu
		"OpenStageMusicMenu", -- server -> client: (station snapshot) open the stage music menu
		"StageMusicControl", -- client -> server: ({ action, stationId, trackId }) control nearby stage music
		"WeatherStateUpdated", -- server -> client: (weather snapshot) authoritative weather/blackout state
	},
	RemoteFunctions = {
		"GetCharacters", -- client -> server: () -> array of {citizenId, cid, firstname, lastname}
		"SelectCharacter", -- client -> server: (citizenId) -> boolean, errorMessage?
		"CreateCharacter", -- client -> server: (firstname, lastname) -> citizenId, errorMessage?
		"DeleteCharacter", -- client -> server: (citizenId) -> boolean, errorMessage?
		"SaveAppearance", -- client -> server: (serializedAppearance) -> boolean, errorMessage?
		"GetInventory", -- client -> server: () -> inventory snapshot
		"MoveInventoryItem", -- client -> server: (fromSlot, toSlot) -> boolean, errorMessage?
		"GiveInventoryItem", -- client -> server: (slot) -> boolean, errorMessage?
		"UseInventorySlot", -- client -> server: (slot) -> boolean, errorMessage?
		"RequestRespawn", -- client -> server: () -> boolean, errorMessage?
		"GetAdminContext", -- client -> server: () -> admin menu snapshot, permission checked
		"AdminAction", -- client -> server: (action, payload) -> boolean, resultOrError
	},
}
