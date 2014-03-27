#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <morecolors>
#include <steamtools>

#define PLUGIN_VERSION "1.2.4"

#define TF_CLASS_DEMOMAN		4
#define TF_CLASS_ENGINEER		9
#define TF_CLASS_HEAVY			6
#define TF_CLASS_MEDIC			5
#define TF_CLASS_PYRO			7
#define TF_CLASS_SCOUT			1
#define TF_CLASS_SNIPER			2
#define TF_CLASS_SOLDIER		3
#define TF_CLASS_SPY			8
#define TF_CLASS_UNKNOWN		0

#define TF_TEAM_RED				2
#define TF_TEAM_BLU				3

#define VOTE_NO					"###no###"
#define VOTE_YES				"###yes###"

new Handle:voteMenu=INVALID_HANDLE;
new Handle:voteDelayTimer=INVALID_HANDLE;

new voted[MAXPLAYERS+1]={false, ...};
new bool:voteAllowed=true;
new voteDelay=0;

//This code is based on the Class Restrictions Mod from Tsunami: http://forums.alliedmods.net/showthread.php?t=73104

public Plugin:myinfo=
{
	name="Class Warfare",
	author="Tsunami, JonathanFlynn, 50DKP",
	description="Class Vs Class",
	version=PLUGIN_VERSION,
	url="https://github.com/JonathanFlynn/Class-Warfare"
}

new clientClass[MAXPLAYERS+1];
new Handle:cvarEnabled;
new Handle:cvarFlags;
new Handle:cvarImmunity;
new Handle:cvarClassChangeInterval;
new Float:classLimits[4][10];
new String:classSounds[10][24]={"", "vo/scout_no03.wav", "vo/sniper_no04.wav", "vo/soldier_no01.wav", "vo/demoman_no03.wav", "vo/medic_no03.wav", "vo/heavy_no02.wav", "vo/pyro_no01.wav", "vo/spy_no02.wav", "vo/engineer_no03.wav"};

static String:ClassNames[TFClassType][]={"", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer"};

new blueClass;
new redClass;

new RandomizedThisRound=0;

public OnPluginStart()
{
	CreateConVar("sm_classwarfare_version", PLUGIN_VERSION, "Class Warfare version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	cvarEnabled=CreateConVar("sm_classwarfare_enabled", "1", "Enable/disable Class Warfare");
	cvarFlags=CreateConVar("sm_classwarfare_flags", "", "Admin flags for restricted classes");
	cvarImmunity=CreateConVar("sm_classwarfare_immunity", "0", "Enable/disable admins being immune for restricted classes");
	cvarClassChangeInterval=CreateConVar("sm_classwarfare_change_interval", "0", "Shuffle the classes every x minutes, or 0 for round only");

	RegAdminCmd("sm_classwarfare_change", ForceChangeClass, ADMFLAG_VOTE, "Change the classes around!  Optionally, you can specify the classes you want it to change to.");
	RegConsoleCmd("sm_classwarfare_vote", Vote_ChangeClass, "Vote to change the classes!");
	RegConsoleCmd("sm_classwarfare_help", Command_Help, "Find out what classes are in play and some other help!");

	HookEvent("player_changeclass", OnChangeClass);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_team", OnChangeTeam);
	HookEvent("teamplay_round_start", OnRoundStart);
	HookEvent("teamplay_setup_finished", OnSetupFinished);
	HookEvent("teamplay_round_win", OnRoundEnd);

	LoadTranslations("basevotes.phrases");
	LoadTranslations("common.phrases");
}

public OnConfigsExecuted()
{
	CreateTimer(120.0, Timer_Announce);

	decl String:description[64];
	Format(description, sizeof(description), "Class Warfare %s", PLUGIN_VERSION);
	Steam_SetGameDescription(description);
}

public OnMapStart()
{
	SetupClassRestrictions();

	decl String:sound[32];
	for(new i=1; i<sizeof(classSounds); i++)
	{
		Format(sound, sizeof(sound), "sound/%s", classSounds[i]);
		PrecacheSound(classSounds[i]);
		AddFileToDownloadsTable(sound);
	}
}

public OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GetEventInt(event, "full_round")==1) 
	{
		RandomizedThisRound=0;
	}
}

public OnClientPutInServer(client)
{
	clientClass[client]=TF_CLASS_UNKNOWN;
}

public OnChangeClass(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!GetConVarBool(cvarEnabled))
	{
		return;
	}

	new client=GetClientOfUserId(GetEventInt(event, "userid")),
	class=GetEventInt(event, "class");

	if(!IsValidClass(client, class))
	{
		EmitSoundToClient(client, classSounds[class]);
		PrintCenterText(client, "%s%s%s%s%s", ClassNames[class],  " is not an option this round! It's Red ", ClassNames[redClass], " vs Blue ", ClassNames[blueClass]);
		CPrintToChat(client, "%s%s%s%s%s", ClassNames[class],  " is not an option this round! It's {red}Red ", ClassNames[redClass], "{default} vs {blue}Blue ", ClassNames[blueClass]);
		AssignValidClass(client);
	}	
}

public Action:OnRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	RoundClassRestrictions();
	PrintStatus();
} 

public Action:OnSetupFinished(Handle:event,  const String:name[], bool:dontBroadcast) 
{   
	PrintStatus();
}  

public OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client=GetClientOfUserId(GetEventInt(event, "userid"));  
	new class=_:TF2_GetPlayerClass(client);
	
	if(!IsValidClass(client, class))
	{
		EmitSoundToClient(client, classSounds[class]);
		AssignValidClass(client);
	}
}

public OnChangeTeam(Handle:event,  const String:name[], bool:dontBroadcast)
{
	new client=GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsValidClient(client) && IsValidClass(client, clientClass[client]))
	{
		EmitSoundToClient(client, classSounds[clientClass[client]]);
		AssignValidClass(client);
	}
}

stock bool:IsValidClass(client, class)
{
	if(!IsValidClient(client))
	{
		return false;
	}

	new team=GetClientTeam(client);
	if(!(GetConVarBool(cvarImmunity) && IsImmune(client)) && IsClassFull(team, class))
	{
		return false;
	}
	return true;   
}

stock bool:IsClassFull(team, class)
{
	if(!GetConVarBool(cvarEnabled) || team<TF_TEAM_RED || class<TF_CLASS_SCOUT)
	{
		return false;
	}

	new limit, Float:actualLimit=classLimits[team][class];

	if(actualLimit>0.0 && actualLimit<1.0)
	{
		limit=RoundToNearest(actualLimit*GetTeamClientCount(team));
	}
	else
	{
		limit=RoundToNearest(actualLimit);
	}

	if(limit==-1)
	{
		return false;
	}
	else if(limit==0)
	{
		return true;
	}

	for(new client=1, count=0; client<=MaxClients; client++)
	{
		if(IsValidClient(client) && GetClientTeam(client)==team && _:TF2_GetPlayerClass(team)==class && ++count>limit)
		{
			return true;
		}
	}
	return false;
}

PrintStatus()
{
	if(!GetConVarBool(cvarEnabled))
	{
		return;
	}

	PrintCenterTextAll("%s%s%s%s", "This is Class Warfare: Red ", ClassNames[redClass], " vs Blue ", ClassNames[blueClass]);
	CPrintToChatAll("%s%s%s%s", "This is Class Warfare: {red}Red ", ClassNames[redClass], "{default} vs {blue}Blue ", ClassNames[blueClass]);
}

stock bool:IsImmune(client)
{
	if(!client || !IsValidClient(client))
	{
		return false;
	}

	decl String:flags[32];
	GetConVarString(cvarFlags, flags, sizeof(flags));
	return !StrEqual(flags, "") && GetUserFlagBits(client) & (ReadFlagString(flags)|ADMFLAG_ROOT);
}

AssignPlayerClasses()
{
	for(new client=1; client<=MaxClients; client++)
	{
		if(IsClientConnected(client) && (!IsValidClass(client, clientClass[client])))
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
	for(new class=TF_CLASS_SCOUT; class<=TF_CLASS_ENGINEER; class++)
	{
		classLimits[TF_TEAM_BLU][class]=0.0;
		classLimits[TF_TEAM_RED][class]=0.0;
	}

	if(randomize)
	{
		blueClass=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
		redClass=GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
	}

	classLimits[TF_TEAM_BLU][blueClass]=-1.0;
	classLimits[TF_TEAM_RED][redClass]=-1.0; 

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
}

AssignValidClass(client)
{
	if(!IsValidClient(client))
	{
		return;
	}

	for(new class=(TF_CLASS_SCOUT, TF_CLASS_ENGINEER), finalClass=class, team=GetClientTeam(client);;)
	{
		if(!IsClassFull(team, class))
		{
			TF2_SetPlayerClass(client, TFClassType:class);
			TF2_RegeneratePlayer(client);  
			if(!IsPlayerAlive(client))
			{
				TF2_RespawnPlayer(client);
			}
			clientClass[client]=class;
			break;
		}
		else if(++class>TF_CLASS_ENGINEER)
		{
			class=TF_CLASS_SCOUT;
		}
		else if(class==finalClass)
		{
			break;
		}
	}
}

public Action:Timer_Announce(Handle:timer)
{
	switch(GetRandomInt(0, 1))
	{
		case 0:
		{
			CPrintToChatAll("{red}[Class Warfare]{default} Very confused about what's going on?  Try {red}!classwarfare_help{default}");
		}
		case 1:
		{
			CPrintToChatAll("{red}[Class Warfare]{default} Don't like the current classes?  Try {red}!classwarefare_vote{default}");
		}
	}
	return Plugin_Continue;
}

public Action:ForceChangeClass(client, args)
{
	if(!IsValidClient(client))
	{
		CReplyToCommand(client, "{red}[Class Warfare]{default} This command must be used in-game and without RCON.");
		return Plugin_Handled;
	}

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
				CPrintToChat(client, "{red}[Class Warfare]{default} Invalid class for blue team!");
				randomize=1;
			}
			CreateTimer(0.0, Timer_Change_Class, randomize);
		}
		default:
		{
			CPrintToChat(client, "{red}[Class Warfare]{default} sm_classwarfare_change <red class> <blue class>");
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

	DisplayVote(client);
	return Plugin_Handled;
}

DisplayVote(client)
{
	LogAction(client, -1, "\"%L\" initiated a Class Warfare vote", client);

	voteMenu=CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);

	SetMenuTitle(voteMenu, "Randomize classes again?");
	AddMenuItem(voteMenu, VOTE_YES, "Yes");
	AddMenuItem(voteMenu, VOTE_NO, "No");

	SetMenuExitButton(voteMenu, false);
	VoteMenuToAll(voteMenu, 20);
}

public Handler_VoteCallback(Handle:menu, MenuAction:action, client, menuPosition)
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
			Format(buffer, sizeof(buffer), "%T", display, client);
			return RedrawMenuItem(buffer);
		}
	}
	else if(action==MenuAction_VoteCancel && client==VoteCancel_NoVotes)
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
		GetMenuItem(menu, client, item, sizeof(item));
		
		if(strcmp(item, VOTE_NO)==0 && client==1)
		{
			votes=totalVotes-votes;
		}

		percent=FloatDiv(float(votes), float(totalVotes));

		if((strcmp(item, VOTE_YES)==0 && FloatCompare(percent, limit)<0 && client==0) || (strcmp(item, VOTE_NO)==0 && client==1))
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