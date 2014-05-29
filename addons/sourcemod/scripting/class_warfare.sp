//JonathanFlynn's code is based on the Class Restrictions Mod from Tsunami: http://forums.alliedmods.net/showthread.php?t=73104
//Updated by 50DKP using JonathanFlynn's version: https://github.com/JonathanFlynn/Class-Warfare
//v2 gets rid of the class limit code left from the Class Restrictions plugin and vastly streamlines the code

#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <morecolors>
#include <steamtools>

#define PLUGIN_VERSION "2.0.0"

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

new Handle:voteMenu=INVALID_HANDLE;
new Handle:voteDelayTimer=INVALID_HANDLE;

new voted[MAXPLAYERS+1]={false, ...};
new bool:voteAllowed=true;
new voteDelay=0;


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

new String:classSounds[10][24]={"", "vo/scout_no03.wav", "vo/sniper_no04.wav", "vo/soldier_no01.wav", "vo/demoman_no03.wav", "vo/medic_no03.wav", "vo/heavy_no02.wav", "vo/pyro_no01.wav", "vo/spy_no02.wav", "vo/engineer_no03.wav"};

static String:ClassNames[TFClassType][]={"", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer"};

new blueClass;
new redClass;

new RandomizedThisRound=0;

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
	HookEvent("teamplay_round_win", OnRoundEnd);

	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");
}

public OnConfigsExecuted()
{
	enabled=GetConVarBool(cvarEnabled);
	if(enabled)
	{
		immune=GetConVarBool(cvarImmune);
		CreateTimer(120.0, Timer_Announce, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		UpdateGameDescription(true);
	}
}

public OnCvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(convar==cvarEnabled)
	{
		enabled=bool:StringToInt(newValue);
		UpdateGameDescription(enabled);
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
} 

public Action:OnSetupFinished(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(enabled)
	{
		PrintStatus();
	}
}

public OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(enabled && GetEventInt(event, "full_round")==1)
	{
		RandomizedThisRound=0;
	}
}

public OnClassAssigned(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(enabled)
	{
		CheckClass(GetClientOfUserId(GetEventInt(event, "userid")), GetEventInt(event, "class"));
	}
}

CheckClass(client, class)
{
	if(!IsValidClass(client, class))
	{
		EmitSoundToClient(client, classSounds[class]);
		PrintCenterText(client, "%s%s%s%s%s", ClassNames[class],  " is not an option this round! It's Red ", ClassNames[redClass], " vs Blue ", ClassNames[blueClass]);
		CPrintToChat(client, "%s%s%s%s%s", ClassNames[class],  " is not an option this round! It's {red}Red ", ClassNames[redClass], "{default} vs {blue}Blue ", ClassNames[blueClass]);
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
	PrintCenterTextAll("%s%s%s%s", "This is Class Warfare: Red ", ClassNames[redClass], " vs Blue ", ClassNames[blueClass]);
	CPrintToChatAll("%s%s%s%s", "This is Class Warfare: {red}Red ", ClassNames[redClass], "{default} vs {blue}Blue ", ClassNames[blueClass]);
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

RoundClassRestrictions()
{
	if(RandomizedThisRound==0)
	{
		SetupClassRestrictions();
	} 
	RandomizedThisRound=1;
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
	PrintCenterTextAll("%s%s%s%s", "Mid Round Class Change: Red ", ClassNames[redClass], " vs Blue ", ClassNames[blueClass]);
	CPrintToChatAll("%s%s%s%s", "Mid Round Class Change: {red}Red ", ClassNames[redClass], "{default} vs {blue}Blue ", ClassNames[blueClass]);

	for(new client=1; client<=MaxClients; client++)
	{
		if(IsValidClient(client))
		{
			AssignValidClass(client);
		}
	}
}

AssignValidClass(client)
{
	TF2_SetPlayerClass(client, (GetClientTeam(client)==TF_TEAM_RED ? (TFClassType:redClass) : (TFClassType:blueClass)));
	TF2_RegeneratePlayer(client);
	if(!IsPlayerAlive(client))
	{
		TF2_RespawnPlayer(client);
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

	if(!voteAllowed)
	{
		CPrintToChat(client, "{red}[Class Warfare]{default} You must wait %i seconds until creating another vote", voteDelay);
	}

	DisplayVote(client, 0);
	return Plugin_Handled;
}

DisplayVote(client, mode)
{
	if(mode==0)
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
		voteMenu=CreateMenu(Handler_VoteChooseClass, MenuAction:MENU_ACTIONS_ALL);

		SetMenuTitle(voteMenu, "Choose your classes!");
		for(new i=1; i<=5; i++)  //Probably a much cleaner way of doing this, but eh
		{
			new class1=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
			new class2=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
			decl String:info[4];
			decl String:display[20];
			decl String:display1[10];
			decl String:display2[10];
			switch(class1)
			{
				case 1:
				{
					Format(display1, sizeof(display1), "Scout");
				}
				case 2:
				{
					Format(display1, sizeof(display1), "Soldier");
				}
				case 3:
				{
					Format(display1, sizeof(display1), "Pyro");
				}
				case 4:
				{
					Format(display1, sizeof(display1), "Demoman");
				}
				case 5:
				{
					Format(display1, sizeof(display1), "Heavy");
				}
				case 6:
				{
					Format(display1, sizeof(display1), "Engineer");
				}
				case 7:
				{
					Format(display1, sizeof(display1), "Medic");
				}
				case 8:
				{
					Format(display1, sizeof(display1), "Sniper");
				}
				case 9:
				{
					Format(display1, sizeof(display1), "Spy");
				}
			}

			switch(class2)
			{
				case 1:
				{
					Format(display2, sizeof(display2), "Scout");
				}
				case 2:
				{
					Format(display2, sizeof(display2), "Soldier");
				}
				case 3:
				{
					Format(display2, sizeof(display2), "Pyro");
				}
				case 4:
				{
					Format(display2, sizeof(display2), "Demoman");
				}
				case 5:
				{
					Format(display2, sizeof(display2), "Heavy");
				}
				case 6:
				{
					Format(display2, sizeof(display2), "Engineer");
				}
				case 7:
				{
					Format(display2, sizeof(display2), "Medic");
				}
				case 8:
				{
					Format(display2, sizeof(display2), "Sniper");
				}
				case 9:
				{
					Format(display2, sizeof(display2), "Spy");
				}
			}
			Format(display, sizeof(display), "%s vs %s", display1, display2);
			Format(info, sizeof(info), "%i", i);
			AddMenuItem(voteMenu, info, display);
			SetMenuExitButton(voteMenu, false);
			VoteMenuToAll(voteMenu, 20);
		}
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
		DelayVote();
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
			DelayVote();
		}
		else
		{
			CPrintToChatAll("{red}[Class Warfare]{default} %t", "Vote Successful", RoundToNearest(100.0*percent), totalVotes);
			CPrintToChatAll("{red}[Class Warfare]{default} Re-rolling classes!");
			LogAction(-1, -1, "[Class Warfare] Changing classes due to vote");
			CreateTimer(0.0, Timer_Change_Class, 1);
			DelayVote(true);
		}
	}
	return 0;
}

public Handler_VoteChooseClass(Handle:menu, MenuAction:action, option, menuPosition)
{
	if(action==MenuAction_End)
	{
		CloseVoteMenu();
	}
	else if(action==MenuAction_Display)
	{
		new Handle:panel=Handle:menuPosition;
		SetPanelTitle(panel, "Choose your classes!");
	}
	else if(action==MenuAction_VoteCancel && option==VoteCancel_NoVotes)
	{
		CPrintToChatAll("{red}[Class Warfare]{default} %t", "No Votes Cast");
	}
	else if(action==MenuAction_VoteEnd)  //Oh this code!
	{
		decl String:item[64], String:display[64], String:classes[16][2];
		GetMenuItem(menu, option, item, sizeof(item));

		if(strcmp(item, VOTE_NO)==0 || strcmp(item, VOTE_YES)==0)
		{
			strcopy(item, sizeof(item), display);
		}
		CPrintToChatAll("{red}[Class Warfare]{default} Vote successful!  This round will be %s!", item);
		ExplodeString(item, " vs ", classes, 16, 2);

		if(strcmp("scout", classes[0], false))
		{
			redClass=TF_CLASS_SCOUT;
		}
		else if(strcmp("soldier", classes[0], false))
		{
			redClass=TF_CLASS_SOLDIER;
		}
		else if(strcmp("pyro", classes[0], false))
		{
			redClass=TF_CLASS_PYRO;
		}
		else if(strcmp("demoman", classes[0], false))
		{
			redClass=TF_CLASS_DEMOMAN;
		}
		else if(strcmp("heavy", classes[0], false))
		{
			redClass=TF_CLASS_HEAVY;
		}
		else if(strcmp("engineer", classes[0], false))
		{
			redClass=TF_CLASS_ENGINEER;
		}
		else if(strcmp("medic", classes[0], false))
		{
			redClass=TF_CLASS_MEDIC;
		}
		else if(strcmp("sniper", classes[0], false))
		{
			redClass=TF_CLASS_SNIPER;
		}
		else if(strcmp("spy", classes[0], false))
		{
			redClass=TF_CLASS_SPY;
		}
		else
		{
			redClass=TF_CLASS_UNKNOWN;
		}

		if(strcmp("scout", classes[1], false))
		{
			blueClass=TF_CLASS_SCOUT;
		}
		else if(strcmp("soldier", classes[1], false))
		{
			blueClass=TF_CLASS_SOLDIER;
		}
		else if(strcmp("pyro", classes[1], false))
		{
			blueClass=TF_CLASS_PYRO;
		}
		else if(strcmp("demoman", classes[1], false))
		{
			blueClass=TF_CLASS_DEMOMAN;
		}
		else if(strcmp("heavy", classes[1], false))
		{
			blueClass=TF_CLASS_HEAVY;
		}
		else if(strcmp("engineer", classes[1], false))
		{
			blueClass=TF_CLASS_ENGINEER;
		}
		else if(strcmp("medic", classes[1], false))
		{
			blueClass=TF_CLASS_MEDIC;
		}
		else if(strcmp("sniper", classes[1], false))
		{
			blueClass=TF_CLASS_SNIPER;
		}
		else if(strcmp("spy", classes[1], false))
		{
			blueClass=TF_CLASS_SPY;
		}
		else
		{
			blueClass=TF_CLASS_UNKNOWN;
		}

		CreateTimer(0.0, Timer_Change_Class, 0);
	}
	return 0;
}

DelayVote(bool:success=false)
{
    for(new client=0; client<=MaxClients; client++)
	{
		voted[client]=false;
	}

    voteAllowed=false;
    if(voteDelayTimer!=INVALID_HANDLE)
    {
        KillTimer(voteDelayTimer);
        voteDelayTimer=INVALID_HANDLE;
    }

    voteDelay=60;
    if(success)
	{
        voteDelay*=2;
    }
    voteDelayTimer=CreateTimer(float(voteDelay), TimerEnable, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:TimerEnable(Handle:timer)
{
    voteAllowed=true;
    voteDelayTimer=INVALID_HANDLE;
    return Plugin_Handled;
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
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	CPrintToChat(client, "{red}[Class Warfare]{default} Class Warfare pits two classes against each other.  You cannot change your class.");
	CPrintToChat(client, "{red}[Class Warfare]{default} At the end of each full round, classes are re-randomized.");
	CPrintToChat(client, "{red}[Class Warfare]{default} If you feel like the classes are unfair, try voting to change the classes by using {red}!classwarfare_vote{default}.");
	CPrintToChat(client, "{red}[Class Warfare]{default} It is currently {red}Red %s{default} vs {blue} Blue %s{default}!", ClassNames[redClass], ClassNames[blueClass]);
	return Plugin_Handled;
}