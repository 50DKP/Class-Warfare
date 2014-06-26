//JonathanFlynn's code is based on the Class Restrictions Mod from Tsunami: http://forums.alliedmods.net/showthread.php?t=73104
//Updated by 50DKP using JonathanFlynn's version: https://github.com/JonathanFlynn/Class-Warfare
//v2 gets rid of the class limit code left from the Class Restrictions plugin and vastly streamlines the code

#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <morecolors>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamtools>
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "2.1.0 Beta"

#define TF_CLASS_UNKNOWN		0
#define TF_CLASS_SCOUT			1
#define TF_CLASS_SNIPER			2
#define TF_CLASS_SOLDIER		3
#define TF_CLASS_DEMOMAN		4
#define TF_CLASS_MEDIC			5
#define TF_CLASS_HEAVY			6
#define TF_CLASS_PYRO			7
#define TF_CLASS_SPY			8
#define TF_CLASS_ENGINEER		9

#define TF_TEAM_RED				2
#define TF_TEAM_BLU				3

#define VOTE_NO					"###no###"
#define VOTE_YES				"###yes###"

#if defined _steamtools_included
new bool:steamtools;
#endif

public Plugin:myinfo=
{
	name="Class Warfare",
	author="Tsunami, JonathanFlynn, 50DKP",
	description="Class Vs Class",
	version=PLUGIN_VERSION,
	url="https://github.com/50DKP/Class-Warfare/"
}

new Handle:cvarEnabled;
new Handle:cvarMode;
new Handle:cvarImmune;
new Handle:cvarFlags;
new Handle:cvarClassChangeInterval;

new bool:enabled;
new bool:immune;

new Handle:voteMenu=INVALID_HANDLE;
new Float:voteDelay;

static String:classSounds[10][24]={"", "vo/scout_no03.wav", "vo/sniper_no04.wav", "vo/soldier_no01.wav", "vo/demoman_no03.wav", "vo/medic_no03.wav", "vo/heavy_no02.wav", "vo/pyro_no01.wav", "vo/spy_no02.wav", "vo/engineer_no03.wav"};
static String:classNames[TFClassType][]={"", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer"};

new blueClass;
new redClass;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	#if defined _steamtools_included
	MarkNativeAsOptional("Steam_SetGameDescription");
	#endif
	return APLRes_Success;
}

public OnPluginStart()
{
	CreateConVar("sm_classwarfare_version", PLUGIN_VERSION, "Class Warfare version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	cvarEnabled=CreateConVar("sm_classwarfare_enabled", "1", "Enable/disable Class Warfare", FCVAR_PLUGIN|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	cvarMode=CreateConVar("sm_classwarfare_mode", "0", "0-Classes are picked randomly, 1-Classes are picked by a vote", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarImmune=CreateConVar("sm_classwarfare_immunity", "0", "Enable/disable admins being immune to class restrictions", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarFlags=CreateConVar("sm_classwarfare_flags", "", "Admin flags required for immunity (requires sm_classwarfare_immunity to be 1)");
	cvarClassChangeInterval=CreateConVar("sm_classwarfare_change_interval", "0", "Shuffle the classes every x minutes, or 0 for round only", FCVAR_PLUGIN, true, 0.0);

	HookConVarChange(cvarEnabled, OnCvarChange);
	HookConVarChange(cvarImmune, OnCvarChange);

	RegAdminCmd("sm_classwarfare_change", ForceChangeClass, ADMFLAG_VOTE, "Change the classes around!  Optionally, you can specify the classes you want it to change to.");
	RegConsoleCmd("sm_classwarfare_vote", Vote_ChangeClass, "Vote to change the classes!");
	RegConsoleCmd("sm_classwarfare_help", Command_Help, "Find out what classes are in play and some other help!");

	HookEvent("player_spawn", OnClassAssigned);
	HookEvent("player_changeclass", OnClassAssigned);
	HookEvent("teamplay_round_start", OnRoundStart);
	HookEvent("teamplay_setup_finished", OnSetupFinished);

	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");

	#if defined _steamtools_included
	steamtools=LibraryExists("SteamTools");
	#endif
}

public OnLibraryAdded(const String:name[])
{
	#if defined _steamtools_included
	if(strcmp(name, "SteamTools", false)==0)
	{
		steamtools=true;
	}
	#endif
}

public OnLibraryRemoved(const String:name[])
{
	#if defined _steamtools_included
	if(strcmp(name, "SteamTools", false)==0)
	{
		steamtools=false;
	}
	#endif
}

public OnConfigsExecuted()
{
	enabled=GetConVarBool(cvarEnabled);
	if(enabled)
	{
		immune=GetConVarBool(cvarImmune);
		CreateTimer(120.0, Timer_Announce, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		if(steamtools)
		{
			UpdateGameDescription(true);
		}
	}
}

public OnCvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(convar==cvarEnabled)
	{
		enabled=bool:StringToInt(newValue);
		if(steamtools)
		{
			UpdateGameDescription(enabled);
		}
	}
	else if(convar==cvarImmune)
	{
		immune=bool:StringToInt(newValue);
	}
}

public OnMapStart()
{
	SetupClassRestrictions();

	decl String:sound[32];
	for(new class=1; class<sizeof(classSounds); class++)
	{
		Format(sound, sizeof(sound), "sound/%s", classSounds[class]);
		PrecacheSound(classSounds[class]);
	}
}

public OnMapEnd()
{
	if(steamtools)
	{
		UpdateGameDescription(false);
	}
}

public Action:OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(enabled)
	{
		if(GetConVarBool(cvarMode))
		{
			DisplayVote(0, 1);
		}
		else
		{
			RoundClassRestrictions();
		}
		PrintStatus();
	}
	return Plugin_Continue;
} 

public Action:OnSetupFinished(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(enabled)
	{
		PrintStatus();
	}
	return Plugin_Continue;
}

public Action:OnClassAssigned(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(enabled)
	{
		CheckClass(GetClientOfUserId(GetEventInt(event, "userid")), GetEventInt(event, "class"));
	}
	return Plugin_Continue;
}

CheckClass(client, class)
{
	if(!IsValidClass(client, class))
	{
		EmitSoundToClient(client, classSounds[class]);
		PrintCenterText(client, "%s%s%s%s%s", classNames[class],  " is not an option this round! It's Red ", classNames[redClass], " vs Blue ", classNames[blueClass]);
		CPrintToChat(client, "%s%s%s%s%s", classNames[class],  " is not an option this round! It's {red}Red ", classNames[redClass], "{default} vs {blue}Blue ", classNames[blueClass]);
		AssignValidClass(client);
	}
}

stock bool:IsValidClass(client, class)
{
	if(!IsValidClient(client))
	{
		return false;
	}

	if(immune && IsImmune(client))
	{
		return true;
	}

	if(class!=(GetClientTeam(client)==TF_TEAM_RED ? redClass : blueClass))
	{
		return false;
	}
	return true;
}

stock bool:IsImmune(client)
{
	if(!IsValidClient(client))
	{
		return false;
	}

	decl String:flags[32];
	GetConVarString(cvarFlags, flags, sizeof(flags));
	return !StrEqual(flags, "") && GetUserFlagBits(client) & (ReadFlagString(flags)|ADMFLAG_ROOT);
}

PrintStatus()
{
	PrintCenterTextAll("%s%s%s%s", "This is Class Warfare: Red ", classNames[redClass], " vs Blue ", classNames[blueClass]);
	CPrintToChatAll("%s%s%s%s", "This is Class Warfare: {red}Red ", classNames[redClass], "{default} vs {blue}Blue ", classNames[blueClass]);
}

RoundClassRestrictions(randomize=1)
{
	SetupClassRestrictions(randomize);
	AssignPlayerClasses();
}

SetupClassRestrictions(randomize=1)
{
	if(randomize)
	{
		blueClass=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
		redClass=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
	}

	new seconds=GetConVarInt(cvarClassChangeInterval)*60;
	if(seconds>0)
	{
		CreateTimer(float(seconds), Timer_Change_Class, 1);
	}
}

public Action:Timer_Change_Class(Handle:timer, any:randomize)
{
	SetupClassRestrictions(randomize);
	PrintCenterTextAll("%s%s%s%s", "Mid Round Class Change: Red ", classNames[redClass], " vs Blue ", classNames[blueClass]);
	CPrintToChatAll("%s%s%s%s", "Mid Round Class Change: {red}Red ", classNames[redClass], "{default} vs {blue}Blue ", classNames[blueClass]);

	for(new client=1; client<=MaxClients; client++)
	{
		if(IsValidClient(client))
		{
			AssignValidClass(client);
		}
	}
	return Plugin_Continue;
}

AssignValidClass(client)
{
	if(!IsPlayerAlive(client))
	{
		TF2_SetPlayerClass(client, (GetClientTeam(client)==TF_TEAM_RED ? (TFClassType:redClass) : (TFClassType:blueClass)));
	}
	else
	{
		SetEntProp(client, Prop_Send, "m_lifeState", 2);
		TF2_SetPlayerClass(client, (GetClientTeam(client)==TF_TEAM_RED ? (TFClassType:redClass) : (TFClassType:blueClass)));
		SetEntProp(client, Prop_Send, "m_lifeState", 0);
		TF2_RespawnPlayer(client);
	}
}

AssignPlayerClasses()
{
	for(new client=1; client<=MaxClients; client++)
	{
		if(IsValidClient(client) && !IsValidClass(client, _:TF2_GetPlayerClass(client)))
		{
			AssignValidClass(client);
		}
	}
}

public Action:Timer_Announce(Handle:timer)
{
	switch(GetRandomInt(0, 2))
	{
		case 0:
		{
			CPrintToChatAll("{red}[Class Warfare]{default} Very confused about what's going on?  Try {red}!classwarfare_help{default}");
		}
		case 1:
		{
			CPrintToChatAll("{red}[Class Warfare]{default} Don't like the current classes?  Try {red}!classwarfare_vote{default}");
		}
		case 2:
		{
			CPrintToChatAll("{red}[Class Warfare]{default} Brought to you by {olive}Wliu{default} and {olive}JonathanFlynn{default}");
		}
	}
	return Plugin_Continue;
}

public Action:ForceChangeClass(client, args)
{
	switch(args)
	{
		case 0:
		{
			CreateTimer(0.0, Timer_Change_Class, 1);
		}
		case 2:
		{
			new randomize=0;
			decl String:red[10];
			decl String:blue[10];
			GetCmdArg(1, red, sizeof(red));
			GetCmdArg(2, blue, sizeof(blue));

			if(strcmp(red, "scout", false)==0)
			{
				redClass=TF_CLASS_SCOUT;
			}
			else if(strcmp(red, "soldier", false)==0)
			{
				redClass=TF_CLASS_SOLDIER;
			}
			else if(strcmp(red, "pyro", false)==0)
			{
				redClass=TF_CLASS_PYRO;
			}
			else if(strcmp(red, "demoman", false)==0 || strcmp(red, "demo", false)==0)
			{
				redClass=TF_CLASS_DEMOMAN;
			}
			else if(strcmp(red, "heavy", false)==0 || strcmp(red, "heavyweapons", false)==0)
			{
				redClass=TF_CLASS_HEAVY;
			}
			else if(strcmp(red, "engineer", false)==0 || strcmp(red, "engie", false)==0)
			{
				redClass=TF_CLASS_ENGINEER;
			}
			else if(strcmp(red, "medic", false)==0)
			{
				redClass=TF_CLASS_MEDIC;
			}
			else if(strcmp(red, "sniper", false)==0)
			{
				redClass=TF_CLASS_SNIPER;
			}
			else if(strcmp(red, "spy", false)==0)
			{
				redClass=TF_CLASS_SPY;
			}
			else
			{
				CPrintToChat(client, "{red}[Class Warfare]{default} Invalid class for red team!");
				randomize=1;
			}

			if(strcmp(blue, "scout", false)==0)
			{
				blueClass=TF_CLASS_SCOUT;
			}
			else if(strcmp(blue, "soldier", false)==0)
			{
				blueClass=TF_CLASS_SOLDIER;
			}
			else if(strcmp(blue, "pyro", false)==0)
			{
				blueClass=TF_CLASS_PYRO;
			}
			else if(strcmp(blue, "demoman", false)==0 || strcmp(blue, "demo", false)==0)
			{
				blueClass=TF_CLASS_DEMOMAN;
			}
			else if(strcmp(blue, "heavy", false)==0 || strcmp(blue, "heavyweapons", false)==0)
			{
				blueClass=TF_CLASS_HEAVY;
			}
			else if(strcmp(blue, "engineer", false)==0 || strcmp(blue, "engie", false)==0)
			{
				blueClass=TF_CLASS_ENGINEER;
			}
			else if(strcmp(blue, "medic", false)==0)
			{
				blueClass=TF_CLASS_MEDIC;
			}
			else if(strcmp(blue, "sniper", false)==0)
			{
				blueClass=TF_CLASS_SNIPER;
			}
			else if(strcmp(blue, "spy", false)==0)
			{
				blueClass=TF_CLASS_SPY;
			}
			else
			{
				CReplyToCommand(client, "{red}[Class Warfare]{default} Invalid class for blue team!");
				randomize=1;
			}
			CreateTimer(0.0, Timer_Change_Class, randomize);
		}
		default:
		{
			CReplyToCommand(client, "{red}[Class Warfare]{default} sm_classwarfare_change <red class> <blue class>");
		}
	}
	return Plugin_Handled;
}

public Action:Vote_ChangeClass(client, args)
{
	if(!IsValidClient(client))
	{
		CReplyToCommand(client, "{red}[Class Warfare]{default} This command must be used in-game and without RCON.");
		return Plugin_Handled;
	}

	if(IsVoteInProgress())
	{
		CPrintToChat(client, "{red}[Class Warfare]{default} %t", "Vote in Progress");
		return Plugin_Handled;
	}

	if(GetGameTime()<voteDelay)
	{
		CPrintToChat(client, "{red}[Class Warfare]{default} You must wait %i seconds until creating another vote", RoundFloat(voteDelay-GetGameTime()));
		return Plugin_Handled;
	}

	DisplayVote(client, 0);
	return Plugin_Handled;
}

DisplayVote(client, mode)
{
	if(!mode)
	{
		LogAction(client, -1, "\"%L\" initiated a Class Warfare vote", client);

		voteMenu=CreateMenu(Handler_VoteRandomizeClass, MenuAction:MENU_ACTIONS_ALL);

		SetMenuTitle(voteMenu, "Randomize classes again?");
		AddMenuItem(voteMenu, VOTE_YES, "Yes");
		AddMenuItem(voteMenu, VOTE_NO, "No");

		SetMenuExitButton(voteMenu, false);
		VoteMenuToAll(voteMenu, 20);
	}
	else
	{
		voteMenu=CreateMenu(Handler_VoteChooseClassBasic);
		SetVoteResultCallback(voteMenu, Handler_VoteChooseClass);

		SetMenuTitle(voteMenu, "Choose your classes!");
		for(new i=1; i<=5; i++)  //Probably a much cleaner way of doing this, but eh
		{
			new class1=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
			new class2=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
			decl String:info[2], String:finalDisplay[22], String:display[2][10];
			switch(class1)
			{
				case 1:
				{
					Format(display[0], 10, "Scout");
				}
				case 2:
				{
					Format(display[0], 10, "Soldier");
				}
				case 3:
				{
					Format(display[0], 10, "Pyro");
				}
				case 4:
				{
					Format(display[0], 10, "Demoman");
				}
				case 5:
				{
					Format(display[0], 10, "Heavy");
				}
				case 6:
				{
					Format(display[0], 10, "Engineer");
				}
				case 7:
				{
					Format(display[0], 10, "Medic");
				}
				case 8:
				{
					Format(display[0], 10, "Sniper");
				}
				case 9:
				{
					Format(display[0], 10, "Spy");
				}
			}

			switch(class2)
			{
				case 1:
				{
					Format(display[1], 10, "Scout");
				}
				case 2:
				{
					Format(display[1], 10, "Soldier");
				}
				case 3:
				{
					Format(display[1], 10, "Pyro");
				}
				case 4:
				{
					Format(display[1], 10, "Demoman");
				}
				case 5:
				{
					Format(display[1], 10, "Heavy");
				}
				case 6:
				{
					Format(display[1], 10, "Engineer");
				}
				case 7:
				{
					Format(display[1], 10, "Medic");
				}
				case 8:
				{
					Format(display[1], 10, "Sniper");
				}
				case 9:
				{
					Format(display[1], 10, "Spy");
				}
			}
			Format(finalDisplay, sizeof(finalDisplay), "%s vs %s", display[0], display[1]);
			Format(info, sizeof(info), "%i", i);
			AddMenuItem(voteMenu, info, finalDisplay);
		}
		SetMenuTitle(voteMenu, "Choose your classes!");
		SetMenuExitButton(voteMenu, false);
		VoteMenuToAll(voteMenu, 20);
	}
}

public Handler_VoteRandomizeClass(Handle:menu, MenuAction:action, option, menuPosition)
{
	if(action==MenuAction_End)
	{
		CloseVoteMenu();
	}
	else if(action==MenuAction_Display)
	{
		new Handle:panel=Handle:menuPosition;
		SetPanelTitle(panel, "Re-roll the classes?");
	}
	else if(action==MenuAction_DisplayItem)
	{
		decl String:display[64];
		GetMenuItem(menu, menuPosition, "", 0, _, display, sizeof(display));
		if(strcmp(display, VOTE_NO)==0 || strcmp(display, VOTE_YES)==0)
		{
			decl String:buffer[255];
			Format(buffer, sizeof(buffer), "%T", display, option);
			return RedrawMenuItem(buffer);
		}
	}
	else if(action==MenuAction_VoteCancel && option==VoteCancel_NoVotes)
	{
		CPrintToChatAll("{red}[Class Warfare]{default} %t", "No Votes Cast");
		voteDelay=GetGameTime()+60.0;
	}
	else if(action==MenuAction_VoteEnd)
	{
		decl String:item[64];
		new Float:percent, votes, totalVotes;
		new Float:limit=0.6;

		GetMenuVoteInfo(menuPosition, votes, totalVotes);
		GetMenuItem(menu, option, item, sizeof(item));
		
		if(strcmp(item, VOTE_NO)==0 && option==1)
		{
			votes=totalVotes-votes;
		}

		percent=FloatDiv(float(votes), float(totalVotes));

		if((strcmp(item, VOTE_YES)==0 && FloatCompare(percent, limit)<0 && option==0) || (strcmp(item, VOTE_NO)==0 && option==1))
		{
			CPrintToChatAll("{red}[Class Warfare]{default} %t", "Vote Failed", RoundToNearest(100.0*limit), RoundToNearest(100.0*percent), totalVotes);
			LogAction(-1, -1, "[Class Warfare] Vote failed");
			voteDelay=GetGameTime()+60.0;
		}
		else
		{
			CPrintToChatAll("{red}[Class Warfare]{default} %t", "Vote Successful", RoundToNearest(100.0*percent), totalVotes);
			CPrintToChatAll("{red}[Class Warfare]{default} Re-rolling classes!");
			LogAction(-1, -1, "[Class Warfare] Changing classes due to vote");
			CreateTimer(0.0, Timer_Change_Class, 1);
			voteDelay=GetGameTime()+120.0;
		}
	}
	return 0;
}

public Handler_VoteChooseClassBasic(Handle:menu, MenuAction:action, option, menuPosition)
{
	if(action==MenuAction_End)
	{
		CloseVoteMenu();
	}
	else if(action==MenuAction_VoteCancel && option==VoteCancel_NoVotes)
	{
		CPrintToChatAll("{red}[Class Warfare]{default} No votes cast, randomizing the classes!");
		RoundClassRestrictions();
	}
}

public Handler_VoteChooseClass(Handle:menu, votes, clients, const clientInfo[][2], items, const itemInfo[][2])
{
	decl String:item[2], String:display[22], String:classes[2][18];
	new randomize, winner;
	if(items>1 && (itemInfo[0][VOTEINFO_ITEM_VOTES]==itemInfo[1][VOTEINFO_ITEM_VOTES]))
	{
		winner=GetRandomInt(0, 1);
	}

	GetMenuItem(menu, itemInfo[winner][VOTEINFO_ITEM_INDEX], item, sizeof(item), _, display, sizeof(display));
	ExplodeString(display, " vs ", classes, 2, 18);
	CPrintToChatAll("{red}[Class Warfare]{default} Vote successful!  This round will be {red}Red %s{default} vs {blue}Blue %s{default}!", classes[0], classes[1]);

	if(!strcmp("scout", classes[0], false))
	{
		redClass=TF_CLASS_SCOUT;
	}
	else if(!strcmp("soldier", classes[0], false))
	{
		redClass=TF_CLASS_SOLDIER;
	}
	else if(!strcmp("pyro", classes[0], false))
	{
		redClass=TF_CLASS_PYRO;
	}
	else if(!strcmp("demoman", classes[0], false))
	{
		redClass=TF_CLASS_DEMOMAN;
	}
	else if(!strcmp("heavy", classes[0], false))
	{
		redClass=TF_CLASS_HEAVY;
	}
	else if(!strcmp("engineer", classes[0], false))
	{
		redClass=TF_CLASS_ENGINEER;
	}
	else if(!strcmp("medic", classes[0], false))
	{
		redClass=TF_CLASS_MEDIC;
	}
	else if(!strcmp("sniper", classes[0], false))
	{
		redClass=TF_CLASS_SNIPER;
	}
	else if(!strcmp("spy", classes[0], false))
	{
		redClass=TF_CLASS_SPY;
	}
	else
	{
		LogError("[Class Warfare] Class vote returned an unknown class for Red!");
		randomize=1;
	}

	if(!strcmp("scout", classes[1], false))
	{
		blueClass=TF_CLASS_SCOUT;
	}
	else if(!strcmp("soldier", classes[1], false))
	{
		blueClass=TF_CLASS_SOLDIER;
	}
	else if(!strcmp("pyro", classes[1], false))
	{
		blueClass=TF_CLASS_PYRO;
	}
	else if(!strcmp("demoman", classes[1], false))
	{
		blueClass=TF_CLASS_DEMOMAN;
	}
	else if(!strcmp("heavy", classes[1], false))
	{
		blueClass=TF_CLASS_HEAVY;
	}
	else if(!strcmp("engineer", classes[1], false))
	{
		blueClass=TF_CLASS_ENGINEER;
	}
	else if(!strcmp("medic", classes[1], false))
	{
		blueClass=TF_CLASS_MEDIC;
	}
	else if(!strcmp("sniper", classes[1], false))
	{
		blueClass=TF_CLASS_SNIPER;
	}
	else if(!strcmp("spy", classes[1], false))
	{
		blueClass=TF_CLASS_SPY;
	}
	else
	{
		LogError("[Class Warfare] Class vote returned an unknown class for Blue!");
		randomize=1;
	}

	//CreateTimer(0.0, Timer_Change_Class, randomize);
	RoundClassRestrictions(randomize);
	return;
}

CloseVoteMenu()
{
	CloseHandle(voteMenu);
	voteMenu=INVALID_HANDLE;
}

UpdateGameDescription(bool:enable)
{
	if(enable)
	{
		decl String:description[64];
		Format(description, sizeof(description), "Class Warfare %s", PLUGIN_VERSION);
		Steam_SetGameDescription(description);
	}
	else
	{
		Steam_SetGameDescription("Team Fortress");
	}
}

stock bool:IsValidClient(client, bool:replay=true)
{
	if(client<=0 || client>MaxClients || !IsClientInGame(client) || GetEntProp(client, Prop_Send, "m_bIsCoaching"))
	{
		return false;
	}

	if(replay && (IsClientSourceTV(client) || IsClientReplay(client)))
	{
		return false;
	}
	return true;
}

public Action:Command_Help(client, args)
{
	if(IsValidClient(client))
	{
		CPrintToChat(client, "{red}[Class Warfare]{default} Class Warfare pits two classes against each other.  You cannot change your class.");
		CPrintToChat(client, "{red}[Class Warfare]{default} At the end of each full round, classes are re-randomized.");
		CPrintToChat(client, "{red}[Class Warfare]{default} If you feel like the classes are unfair, try voting to change the classes by using {red}!classwarfare_vote{default}.");
		CPrintToChat(client, "{red}[Class Warfare]{default} It is currently {red}Red %s{default} vs {blue}Blue %s{default}!", classNames[redClass], classNames[blueClass]);
	}
	return Plugin_Handled;
}