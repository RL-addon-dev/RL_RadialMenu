--[[
    Share strings: any plain Lua data as one text string players can copy and paste (sharing
    profiles, layouts, lists...). Blizzard's own encoding (C_EncodingUtil): CBOR, then Deflate,
    then base64.

    A header travels inside the encoded data, next to the payload, so it can't be edited by hand:
    which addon made the string, its format version, and the game it came from.

        local text = ShareString.Encode({ addon = "MYADDON", version = 1, game = "retail" }, payload)

        local payload, header = ShareString.Decode(text, {
            addon      = "MYADDON",   -- strings made by anything else are refused
            maxVersion = 1,           -- newer formats are refused (made by a newer version)
            game       = "retail",    -- strings from another game are refused (nil: any game)
            maxLength  = 200000,      -- longer text is refused before decoding (default below)
        })

        Refused: payload is nil, the second return is the reason (a ShareString.Error), and the
        third is the header when it could still be read (for "this string is for WoW Forever").

    Decoding never raises: damaged or edited text comes back as ShareString.Error.Invalid.
    Encoding only stops casual edits; whoever reads the payload must still validate it.
]]

local env = select(2, ...)
local ShareString = env.AX_Modules:New("ax_modules\\share-string")

local pcall, type, gsub = pcall, type, string.gsub

local DEFAULT_MAX_LENGTH = 200000 -- characters of encoded text

ShareString.Error = {
    Empty        = "empty",         -- nothing pasted
    TooLong      = "too-long",      -- over maxLength
    Invalid      = "invalid",       -- not a share string, or damaged / edited
    OtherAddon   = "other-addon",   -- made by another addon
    NewerVersion = "newer-version", -- a format this version doesn't know yet
    OtherGame    = "other-game",    -- made in another game (retail / classic ...)
}

--- Whether this client has the encoding functions (retail, classic era and WoW Forever do).
function ShareString.IsSupported()
    return C_EncodingUtil ~= nil and C_EncodingUtil.SerializeCBOR ~= nil
end

--- @param header table { addon = string, version = number, game = string }
--- @param payload any plain data: tables, strings, numbers, booleans
--- @return string text
function ShareString.Encode(header, payload)
    local envelope = { addon = header.addon, version = header.version, game = header.game, data = payload }
    local cbor = C_EncodingUtil.SerializeCBOR(envelope)
    local compressed = C_EncodingUtil.CompressString(cbor, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    return C_EncodingUtil.EncodeBase64(compressed)
end

local function DecodeEnvelope(text)
    local ok, compressed = pcall(C_EncodingUtil.DecodeBase64, text)
    if not ok or type(compressed) ~= "string" or compressed == "" then return nil end
    local cbor
    ok, cbor = pcall(C_EncodingUtil.DecompressString, compressed, Enum.CompressionMethod.Deflate)
    if not ok or type(cbor) ~= "string" then return nil end
    local envelope
    ok, envelope = pcall(C_EncodingUtil.DeserializeCBOR, cbor)
    if not ok or type(envelope) ~= "table" then return nil end
    return envelope
end

--- @param text string what the player pasted (spaces and line breaks are ignored)
--- @param expect table { addon, maxVersion, game?, maxLength? }
--- @return any payload nil when refused
--- @return table|string headerOrError the header, or the ShareString.Error when refused
--- @return table? refusedHeader when refused after the header could be read
function ShareString.Decode(text, expect)
    text = type(text) == "string" and gsub(text, "%s+", "") or ""
    if text == "" then return nil, ShareString.Error.Empty end
    if #text > (expect.maxLength or DEFAULT_MAX_LENGTH) then return nil, ShareString.Error.TooLong end

    local envelope = DecodeEnvelope(text)
    if not envelope or type(envelope.version) ~= "number" or envelope.data == nil then
        return nil, ShareString.Error.Invalid
    end
    local header = { addon = envelope.addon, version = envelope.version, game = envelope.game }
    if envelope.addon ~= expect.addon then return nil, ShareString.Error.OtherAddon, header end
    if envelope.version > expect.maxVersion then return nil, ShareString.Error.NewerVersion, header end
    if expect.game and envelope.game ~= expect.game then return nil, ShareString.Error.OtherGame, header end
    return envelope.data, header
end
