#include <sourcemod>
#include <shavit>
#include <discordWebhookAPI>

#undef REQUIRE_EXTENSIONS
#include <ripext>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.4"

bool   g_bRIPExt = false;

char   g_cHostname[128];
char   g_cCurrentMap[PLATFORM_MAX_PATH];
char   g_szApiKey[64];
char   g_szPictureURL[1024];

ConVar g_cvHostname;
ConVar g_cvWebhook;
ConVar g_cvMinimumrecords;
ConVar g_cvThumbnailUrlRoot;
ConVar g_cvBotUsername;
ConVar g_cvFooterUrl;
ConVar g_cvMainEmbedColor;
ConVar g_cvBonusEmbedColor;
ConVar g_cvSteamWebAPIKey;

public Plugin myinfo =
{
    name        = "[shavit] Discord WR Bot",
    author      = "SlidyBat, improved by Sarrus, updated by goodtrailer",
    description = "Makes discord bot post message when server WR is beaten",
    version     = PLUGIN_VERSION,
    url         = "https://steamcommunity.com/id/SlidyBat2",
}

public void OnPluginStart()
{
    g_cvMinimumrecords   = CreateConVar("sm_bhop_discord_min_record", "0", "Minimum number of records before they are sent to the discord channel.", _, true, 0.0);
    g_cvWebhook          = CreateConVar("sm_bhop_discord_webhook", "", "The webhook to the discord channel where you want record messages to be sent.", FCVAR_PROTECTED);
    g_cvThumbnailUrlRoot = CreateConVar("sm_bhop_discord_thumbnail_root_url", "https://image.gametracker.com/images/maps/160x120/csgo/${mapname}.jpg", "The base url of where the Discord images are stored. Leave blank to disable.");
    g_cvBotUsername      = CreateConVar("sm_bhop_discord_username", "", "Username of the bot");
    g_cvFooterUrl        = CreateConVar("sm_bhop_discord_footer_url", "https://upload.wikimedia.org/wikipedia/commons/thumb/4/42/Counter-Strike_CS_logo.svg/250px-Counter-Strike_CS_logo.svg.png", "The url of the footer icon, leave blank to disable.");
    g_cvMainEmbedColor   = CreateConVar("sm_bhop_discord_main_color", "#00ffff", "Color of embed for when main wr is beaten");
    g_cvBonusEmbedColor  = CreateConVar("sm_bhop_discord_bonus_color", "#ff0000", "Color of embed for when bonus wr is beaten");
    g_cvSteamWebAPIKey   = CreateConVar("kzt_discord_steam_api_key", "", "Allows the use of the player profile picture, leave blank to disable. The key can be obtained here: https://steamcommunity.com/dev/apikey", FCVAR_PROTECTED);

    g_cvHostname         = FindConVar("hostname");
    g_cvHostname.GetString(g_cHostname, sizeof(g_cHostname));
    g_cvHostname.AddChangeHook(onConVarChanged);

    RegAdminCmd("sm_discordtest", commandDiscordTest, ADMFLAG_ROOT);

    GetConVarString(g_cvSteamWebAPIKey, g_szApiKey, sizeof g_szApiKey);

    AutoExecConfig(true, "plugin.shavit-discord");
}

public void OnAllPluginsLoaded()
{
    g_bRIPExt = LibraryExists("ripext");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "ripext"))
        g_bRIPExt = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "ripext"))
        g_bRIPExt = false;
}

void onConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_cvHostname.GetString(g_cHostname, sizeof(g_cHostname));
}

public void OnMapStart()
{
    GetCurrentMap(g_cCurrentMap, sizeof g_cCurrentMap);
    removeWorkshop(g_cCurrentMap, sizeof g_cCurrentMap);
    GetConVarString(g_cvSteamWebAPIKey, g_szApiKey, sizeof g_szApiKey);
}

Action commandDiscordTest(int client, int args)
{
    Shavit_OnWorldRecord(client, 1, 12.3, 35, 23, 93.25, 1, 14.01, 14.5, 82.3, 0.0, 0.0, 0);
    PrintToChat(client, "[shavit-discord] Discord Test Message has been sent.");
    return Plugin_Continue;
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
    if (GetConVarInt(g_cvMinimumrecords) > 0 && Shavit_GetRecordAmount(style, track) < GetConVarInt(g_cvMinimumrecords))    // dont print if its a new record to avoid spam for new maps
        return;

    if (!StrEqual(g_szApiKey, "") && g_bRIPExt)
        getProfilePictureURL(client, style, time, jumps, strafes, sync, track, oldwr, oldtime, perfs);
    else
        sendDiscordAnnouncement(client, style, time, jumps, strafes, sync, track, oldwr, oldtime, perfs);
}

int rgbToInt(char color[64]) {
    int val = 0;
    int length = strlen(color);
    for (int i = 1; i < length; i++)
        val = 256 * val + (color[i] - '0');

    if (val < 0 || val >= 16777216)
        return 0;

    return val;
}

void requestCallback (HTTPResponse response, any value) {
    PrintToServer("[shavit-discord] Response code: %d", response.Status);

    char buf[2048];
    if (!response.Data.ToString(buf, sizeof(buf), JSON_COMPACT))
        PrintToServer("[shavit-discord] Failed to parse JSON response to string");
    else
        PrintToServer("[shavit-discord] JSON response:\n%s", buf);
}

void sendDiscordAnnouncement(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr, float oldtime, float perfs)
{
    char sWebhook[512];
    char szMainColor[64];
    char szBonusColor[64];
    char szBotUsername[128];

    GetConVarString(g_cvWebhook, sWebhook, sizeof(sWebhook));
    GetConVarString(g_cvMainEmbedColor, szMainColor, sizeof(szMainColor));
    GetConVarString(g_cvBonusEmbedColor, szBonusColor, sizeof(szBonusColor));
    GetConVarString(g_cvBotUsername, szBotUsername, sizeof(szBotUsername));

    Webhook webhook = new Webhook();
    webhook.SetUsername(szBotUsername);

    Embed embed = new Embed();
    embed.SetColor(rgbToInt((track == Track_Main) ? szMainColor : szBonusColor));

    char styleName[128];
    Shavit_GetStyleStrings(style, sStyleName, styleName, sizeof(styleName));

    char buffer[512];
    if (track == Track_Main)
        Format(buffer, sizeof(buffer), "__**New World Record**__ | **%s** - **%s**", g_cCurrentMap, styleName);
    else
        Format(buffer, sizeof(buffer), "__**New Bonus #%i World Record**__ | **%s** - **%s**", track, g_cCurrentMap, styleName);
    embed.SetTitle(buffer);

    char steamid[65];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    Format(buffer, sizeof(buffer), "[%N](http://www.steamcommunity.com/profiles/%s)", client, steamid);
    embed.AddField(new EmbedField("Player:", buffer, true));

    char szOldTime[128];
    FormatSeconds(time, buffer, sizeof(buffer));
    FormatSeconds(time - oldtime, szOldTime, sizeof(szOldTime));

    Format(buffer, sizeof(buffer), "%ss (%ss)", buffer, szOldTime);
    embed.AddField(new EmbedField("Time:", buffer, true));

    FormatSeconds(oldwr, szOldTime, sizeof(szOldTime));
    Format(szOldTime, sizeof(szOldTime), "%ss", szOldTime);
    embed.AddField(new EmbedField("Previous Time:", szOldTime, true));

    Format(buffer, sizeof(buffer), "**Strafes**: %i  **Sync**: %.2f%%  **Jumps**: %i  **Perfect jumps**: %.2f%%", strafes, sync, jumps, perfs);
    embed.AddField(new EmbedField("Stats:", buffer, false));

    // Send the image of the map
    char szUrl[1024];

    GetConVarString(g_cvThumbnailUrlRoot, szUrl, 1024);

    if (!StrEqual(szUrl, ""))
    {
        ReplaceString(szUrl, sizeof szUrl, "${mapname}", g_cCurrentMap);
    }

    if (StrEqual(g_szPictureURL, ""))
    {
        embed.SetThumbnail(new EmbedThumbnail(szUrl));
    }
    else
    {
        embed.SetThumbnail(new EmbedThumbnail(g_szPictureURL));
        embed.SetImage(new EmbedImage(szUrl));
    }

    EmbedFooter footer = new EmbedFooter();

    char szFooterUrl[1024];
    GetConVarString(g_cvFooterUrl, szFooterUrl, sizeof szFooterUrl);
    if (!StrEqual(szFooterUrl, ""))
        footer.SetIconURL(szFooterUrl);

    Format(buffer, sizeof(buffer), "Server: %s", g_cHostname);
    footer.SetText(buffer);

    embed.SetFooter(footer);

    webhook.AddEmbed(embed);
    webhook.Execute(sWebhook, requestCallback);
}

void getProfilePictureURL(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr, float oldtime, float perfs)
{
    HTTPRequest httpRequest;

    DataPack    pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(style);
    pack.WriteCell(time);
    pack.WriteCell(jumps);
    pack.WriteCell(strafes);
    pack.WriteCell(sync);
    pack.WriteCell(track);
    pack.WriteCell(oldwr);
    pack.WriteCell(oldtime);
    pack.WriteCell(perfs);
    pack.Reset();

    char szRequestBuffer[1024];
    char szSteamID[64];

    GetClientAuthId(client, AuthId_SteamID64, szSteamID, sizeof szSteamID, true);

    Format(szRequestBuffer, sizeof szRequestBuffer, "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s&format=json", g_szApiKey, szSteamID);
    httpRequest = new HTTPRequest(szRequestBuffer);
    httpRequest.Get(onResponseReceived, pack);
}

void onResponseReceived(HTTPResponse response, DataPack pack)
{
    pack.Reset();
    int   client  = pack.ReadCell();
    int   style   = pack.ReadCell();
    float time    = pack.ReadCell();
    int   jumps   = pack.ReadCell();
    int   strafes = pack.ReadCell();
    float sync    = pack.ReadCell();
    int   track   = pack.ReadCell();
    float oldwr   = pack.ReadCell();
    float oldtime = pack.ReadCell();
    float perfs   = pack.ReadCell();

    if (response.Status != HTTPStatus_OK)
        return;

    JSONObject objects   = view_as<JSONObject>(response.Data);
    JSONObject Response  = view_as<JSONObject>(objects.Get("response"));
    JSONArray  players   = view_as<JSONArray>(Response.Get("players"));
    int        playerlen = players.Length;

    JSONObject player;
    for (int i = 0; i < playerlen; i++)
    {
        player = view_as<JSONObject>(players.Get(i));
        player.GetString("avatarmedium", g_szPictureURL, sizeof(g_szPictureURL));
        delete player;
    }
    sendDiscordAnnouncement(client, style, time, jumps, strafes, sync, track, oldwr, oldtime, perfs);
}

void removeWorkshop(char[] szMapName, int len)
{
    int  i = 0;
    char szBuffer[16], szCompare[2] = "/";

    // Return if "workshop/" is not in the mapname
    if (ReplaceString(szMapName, len, "workshop/", "", true) != 1)
        return;

    // Find the index of the last /
    do
    {
        szBuffer[i] = szMapName[i];
        i++;
    }
    while (szMapName[i] != szCompare[0]);
    szBuffer[i] = szCompare[0];
    ReplaceString(szMapName, len, szBuffer, "", true);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("HTTPClient.HTTPClient");
    MarkNativeAsOptional("HTTPClient.SetHeader");
    MarkNativeAsOptional("HTTPClient.Get");
    MarkNativeAsOptional("JSONObject.Get");
    MarkNativeAsOptional("JSONObject.GetString");
    MarkNativeAsOptional("HTTPResponse.Status.get");
    MarkNativeAsOptional("JSONArray.Length.get");
    MarkNativeAsOptional("JSONArray.Get");
    MarkNativeAsOptional("HTTPResponse.Data.get");
}
