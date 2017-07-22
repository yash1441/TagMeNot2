#pragma semicolon 1
#define PLUGIN_VERSION "20"

#include <sourcemod>
#include <cstrike>
#include <autoexecconfig>
#include <scp>

new String:g_sCfgPath[PLATFORM_MAX_PATH];

new	Handle:g_hIncludeBots = INVALID_HANDLE;
new bool:g_bIncludeBots;
new	Handle:g_hEnforceTags = INVALID_HANDLE;
new bool:g_bEnforceTags;
new	Handle:g_hGuestTag = INVALID_HANDLE;
new String:g_sGuestTag[14];

new String:g_sTag[MAXPLAYERS + 1][50];
new String:g_sTag2[MAXPLAYERS + 1][50];
new bool:g_bLoaded[MAXPLAYERS + 1] = {false, ...};

public Plugin:myinfo =
{
	name = "[TMN2] Tag Me Not 2",
	author = "Simon",
	description = "Tag Players Using SteamIDs and Admin Flags",
	version = PLUGIN_VERSION,
	url = "yash1441@yahoo.com"
}

public OnPluginStart()
{
	AutoExecConfig_SetFile("tmntags2");
	AutoExecConfig_CreateConVar("tmn_version", PLUGIN_VERSION, "Tag Me Not 2: Version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_hIncludeBots = AutoExecConfig_CreateConVar("tmn_bots", "0", "Do bots get tags? (1 = yes, 0 = no)", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hIncludeBots, OnCVarChange);
	g_bIncludeBots = GetConVarBool(g_hIncludeBots);
	
	g_hEnforceTags = AutoExecConfig_CreateConVar("tmn_enforcetags", "1", "If no matching setup is found then us which tag? (1 =  use the tag stored in tmn_tag, 0 = allow their own clan tags).", FCVAR_NONE, true, 0.0, true, 1.0);
	HookConVarChange(g_hEnforceTags, OnCVarChange);
	g_bEnforceTags = GetConVarBool(g_hEnforceTags);
	
	g_hGuestTag = AutoExecConfig_CreateConVar("tmn_tag", "[Guest]", "Default tag for new players if tmn_enforcetags is 1.");
	HookConVarChange(g_hGuestTag, OnCVarChange);
	GetConVarString(g_hGuestTag, g_sGuestTag, sizeof(g_sGuestTag));

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	RegAdminCmd("sm_rechecktags", Cmd_ResetTags, ADMFLAG_KICK, "Recheck tags for all players in the server.");
	
	HookEvent("player_spawn", Event_Recheck);
	HookEvent("player_team", Event_Recheck);
	BuildPath(Path_SM, g_sCfgPath, sizeof(g_sCfgPath), "configs/tmntags.txt");
	
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i, g_bIncludeBots))
		{
			GetTags(i);
		}
	}
}

public OnCVarChange(Handle:hCVar, const String:sOldValue[], const String:sNewValue[])
{
	if(hCVar == g_hIncludeBots)
	{
		g_bIncludeBots = GetConVarBool(g_hIncludeBots);
	}
	else if(hCVar == g_hEnforceTags)
	{
		g_bEnforceTags = GetConVarBool(g_hEnforceTags);
	}
	else if(hCVar == g_hGuestTag)
	{
		GetConVarString(g_hGuestTag, g_sGuestTag, sizeof(g_sGuestTag));
	}
}

public Action:Cmd_ResetTags(client, iArgs)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i, g_bIncludeBots))
		{
			GetTags(i);
		}
	}
	return Plugin_Continue;
}

public OnClientConnected(client)
{
	g_sTag[client] = "";
	g_bLoaded[client] = false;
}

public OnClientDisconnect(client)
{
	g_sTag[client] = "";
	g_bLoaded[client] = false;
}

public OnClientPostAdminCheck(client)
{
	GetTags(client);
}

public OnClientSettingsChanged(client)
{
	if(IsClientAuthorized(client)) //don't want them to try loading before steam id loads
	{
		CheckTags(client);
	}
}

public Action:Event_Recheck(Handle:hEvent, const String:sName[], bool:bDontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	CheckTags(client);
	return Plugin_Continue;
}

public Action:OnChatMessage(&author, Handle:recipients, String:name[], String:message[])
{
	Format(name, MAXLENGTH_NAME, "%s %s", g_sTag[author], name);		
	return Plugin_Changed;
}

GetTags(client)
{
	if(!FileExists(g_sCfgPath))
	{
		SetFailState("[TMN2] Configuration text file %s not found!", g_sCfgPath);
		return;
	}

	new Handle:rFile = OpenFile(g_sCfgPath, "r");
	
	g_sTag[client] = "";
	g_sTag2[client] = "";
	
	decl String:lBuffer[150], String:sSteamID[MAX_NAME_LENGTH], String:sAltUnivID[MAX_NAME_LENGTH], String:g_sParts2[2][50];
	//decl String:g_sParts[3][30];
	if(IsValidClient(client))
	{
		GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID));
		strcopy(sAltUnivID, sizeof(sAltUnivID), sSteamID);
		if(StrContains(sAltUnivID, "STEAM_1", true) != -1)
		{
			ReplaceString(sAltUnivID, sizeof(sAltUnivID), "STEAM_1", "STEAM_0", true);
		}
		else
		{
			ReplaceString(sAltUnivID, sizeof(sAltUnivID), "STEAM_0", "STEAM_1", true);
		}
	}
	else if(IsFakeClient(client) && g_bIncludeBots) //not a valid player - check if bot and bots allowed
	{
		Format(sSteamID, sizeof(sSteamID), "BOT");
		strcopy(sAltUnivID, sizeof(sAltUnivID), sSteamID);
	}
	else
	{
		CloseHandle(rFile);
		return;
	}
	//new Handle:stringArray = CreateArray(256);
	while (ReadFileLine(rFile, lBuffer, sizeof(lBuffer)))
	{
		ReplaceString(lBuffer, sizeof(lBuffer), "\n", "", false);
		if(!lBuffer[0] || lBuffer[0] == ';' || lBuffer[0] == '/' && lBuffer[1] == '/') 
			continue;
		ExplodeString(lBuffer, ";", g_sParts2, 2, sizeof(g_sParts2[]));
		if (lBuffer[0] == '[')
		{
			strcopy(g_sTag2[client], sizeof(g_sTag2[]), lBuffer);
		}
		else
		{
			if(StrEqual("BOT", g_sParts2[0], false)) //check if BOT config
			{
				if(StrEqual("BOT", sSteamID, false)) //check if player is BOT
				{
					strcopy(g_sTag[client], sizeof(g_sTag[]), g_sTag2[client]);//[Noob] \n Bot
					break;
				}
			}
			else if(StrContains(g_sParts2[0], "STEAM_", true) != -1) //check if steam ID
			{
				if(StrEqual(g_sParts2[0], sSteamID, true) || StrEqual(g_sParts2[0], sAltUnivID, true))
				{
					strcopy(g_sTag[client], sizeof(g_sTag[]), g_sTag2[client]);
					break;
				}
			}
		}
	}
	CloseHandle(rFile);
	/*while (ReadFileLine(rFile, lBuffer, sizeof(lBuffer)))
	{
		ReplaceString(lBuffer, sizeof(lBuffer), "\n", "", false);
		if( !lBuffer[0] || lBuffer[0] == ';' || lBuffer[0] == '/' && lBuffer[1] == '/' ) 
			continue;
		PushArrayString(stringArray, lBuffer);
	}
	CloseHandle(rFile);
	new stringArraySize = GetArraySize(stringArray);
	for(new i = 0; i < stringArraySize; i++)
    {
        // The string which lies in our array under index 'i' is put into lineBuf
		GetArrayString(stringArray, i, lBuffer, sizeof(lBuffer));
        // Output lineBuf and we're done here
		PrintToServer("%s", lBuffer);
		ExplodeString(lBuffer, "-", g_sParts, 3, sizeof(g_sParts[]));
		if(StrEqual("BOT", g_sParts[0], false)) //check if BOT config
		{
			if(StrEqual("BOT", sSteamID, false)) //check if player is BOT
			{
				strcopy(g_sTag[client], sizeof(g_sTag[]), g_sParts[1]);
				break;
			}
		}
		else if(StrContains(g_sParts[0], "STEAM_", true) != -1) //check if steam ID
		{
			if(StrEqual(g_sParts[0], sSteamID, true) || StrEqual(g_sParts[0], sAltUnivID, true))
			{
				strcopy(g_sTag[client], sizeof(g_sTag[]), g_sParts[1]);
				break;
			}
		}
		else if(HasFlags(client, g_sParts[0])) //check if player has defined flags
		{
			strcopy(g_sTag[client], sizeof(g_sTag[]), g_sParts[1]);
			break;
		}
    }*/
	
	g_bLoaded[client] = true;
	CheckTags(client);
}

CheckTags(client)
{	
	if(!g_bLoaded[client])
	{
		GetTags(client);
		return;
	}
	
	if(!StrEqual(g_sTag[client], "", true))
	{
		CS_SetClientClanTag(client, g_sTag[client]);
	}
	else if(g_bEnforceTags)
	{
		strcopy(g_sTag[client], sizeof(g_sTag[]), g_sGuestTag);
		CS_SetClientClanTag(client, g_sTag[client]);
	}
}


bool:IsValidClient(client, bool:bAllowBots = false)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client) || (IsFakeClient(client) && !bAllowBots))
	{
		return false;
	}
	return true;
}