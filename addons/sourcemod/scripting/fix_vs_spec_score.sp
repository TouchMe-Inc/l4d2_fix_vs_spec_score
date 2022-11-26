#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>


public Plugin myinfo = {
	name        = "FixVersusSpecScore",
	author      = "TouchMe",
	description = "Fixes round score for spectator to versus",
	version     = "build_0003",
	url         = "https://github.com/TouchMe-Inc/l4d2_fix_vs_spec_score"
};


#define TEAM_SPECTATOR          1
#define TEAM_INFECTED           3

#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"

// Delay before returning a client back to Spectator.
#define RESPECTATE_DELAY_SECONDS    0.1

// Delay between processing individual clients in a batch.
#define BATCH_STEP_SECONDS          0.5


bool g_bGamemodeAvailable = false;

// Client is currently being respectated (temporarily in Infected).
bool g_bRespectating[MAXPLAYERS + 1];

// Clients waiting for respectate, processed one per BATCH_STEP_SECONDS.
ArrayList g_alPendingQueue = null;
bool g_bQueueProcessing = false;

ConVar g_cvGameMode = null;


public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] sErr, int iErrLen)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvGameMode = FindConVar("mp_gamemode");
	g_cvGameMode.AddChangeHook(OnGamemodeChanged);

	char szGameMode[16];
	g_cvGameMode.GetString(szGameMode, sizeof(szGameMode));
	g_bGamemodeAvailable = IsVersusMode(szGameMode);

	g_alPendingQueue = new ArrayList();

	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

void OnGamemodeChanged(ConVar convar, const char[] szOldGameMode, const char[] szNewGameMode)
{
	g_bGamemodeAvailable = IsVersusMode(szNewGameMode);
}

public void OnClientDisconnect(int iClient)
{
	g_bRespectating[iClient] = false;

	int iIndex = g_alPendingQueue.FindValue(iClient);

	if (iIndex != -1) {
		g_alPendingQueue.Erase(iIndex);
	}
}

/**
 * Called when a client changes team.
 */
public Action Event_PlayerTeam(Event event, const char[] event_name, bool dontBroadcast)
{
	if (!g_bGamemodeAvailable) {
		return Plugin_Continue;
	}

	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (iClient <= 0 || !IsClientInGame(iClient) || IsFakeClient(iClient)) {
		return Plugin_Continue;
	}

	if (g_bRespectating[iClient]) {
		return Plugin_Continue;
	}

	int iOldTeam = event.GetInt("oldteam");
	int iNewTeam = event.GetInt("team");

	// Only transitions INTO Spectator from another team are relevant.
	if (iNewTeam != TEAM_SPECTATOR || iOldTeam == TEAM_SPECTATOR) {
		return Plugin_Continue;
	}

	// Enqueue and make sure the processor is running.
	g_alPendingQueue.Push(iClient);

	if (!g_bQueueProcessing)
	{
		g_bQueueProcessing = true;
		CreateTimer(BATCH_STEP_SECONDS, Timer_ProcessQueue, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

/**
 * Processes one queued client per step to avoid a burst of team changes.
 */
Action Timer_ProcessQueue(Handle timer)
{
	if (g_alPendingQueue.Length == 0)
	{
		g_bQueueProcessing = false;
		return Plugin_Stop;
	}

	int iClient = g_alPendingQueue.Get(0);
	g_alPendingQueue.Erase(0);

	RespectateClient(iClient);

	if (g_alPendingQueue.Length > 0)
	{
		CreateTimer(BATCH_STEP_SECONDS, Timer_ProcessQueue, _, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}

	g_bQueueProcessing = false;
	return Plugin_Stop;
}

/**
 * Forces a client through Infected and back to Spectator.
 *
 * This trick makes the L4D2 client redraw its HUD and pull the
 * actual versus round score, which is otherwise not refreshed
 * while the client stays in Spectator.
 */
void RespectateClient(int iClient)
{
	if (g_bRespectating[iClient]) {
		return;
	}

	// Set the flag BEFORE the team change: ChangeClientTeam synchronously
	// fires player_team, which would otherwise re-trigger respectate.
	g_bRespectating[iClient] = true;

	ChangeClientTeam(iClient, TEAM_INFECTED);

	if (GetClientTeam(iClient) != TEAM_INFECTED)
	{
		g_bRespectating[iClient] = false;
		return;
	}

	CreateTimer(RESPECTATE_DELAY_SECONDS, Timer_TurnClientToSpectate, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Returns a client from Infected back to Spectator.
 */
Action Timer_TurnClientToSpectate(Handle timer, int iUserId)
{
	int iClient = GetClientOfUserId(iUserId);

	if (iClient <= 0) {
		return Plugin_Handled;
	}

	if (IsClientInGame(iClient)) {
		ChangeClientTeam(iClient, TEAM_SPECTATOR);
	}

	g_bRespectating[iClient] = false;

	return Plugin_Handled;
}

/**
 * Returns true if the given game mode string is a Versus mode.
 */
bool IsVersusMode(const char[] szGameMode)
{
	return (StrEqual(szGameMode, GAMEMODE_VERSUS, false)
		|| StrEqual(szGameMode, GAMEMODE_VERSUS_REALISM, false));
}