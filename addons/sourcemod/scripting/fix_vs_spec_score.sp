#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>


public Plugin myinfo = {
    name        = "FixVersusSpecScore",
    author      = "TouchMe",
    description = "Fixes round score for spectator to versus",
    version     = "build_0002",
    url         = "https://github.com/TouchMe-Inc/l4d2_fix_vs_spec_score"
};


// Teams
#define TEAM_SPECTATOR          1
#define TEAM_INFECTED           3

// Gamemode
#define GAMEMODE_VERSUS         "versus"
#define GAMEMODE_VERSUS_REALISM "mutation12"

// Macros
#define IS_REAL_CLIENT(%1)      (IsClientInGame(%1) && !IsFakeClient(%1))
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)


bool g_bGamemodeAvailable = false;

ConVar g_cvGameMode = null;


/**
 * Called before OnPluginStart.
 */
public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] sErr, int iErrLen)
{
    if (GetEngineVersion() != Engine_Left4Dead2) {
        strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2");
        return APLRes_SilentFailure;
    }

    return APLRes_Success;
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
    g_cvGameMode = FindConVar("mp_gamemode");
    g_cvGameMode.AddChangeHook(OnGamemodeChanged);

    char szGameMode[16];
    g_cvGameMode.GetString(szGameMode, sizeof(szGameMode));
    g_bGamemodeAvailable = IsVersusMode(szGameMode);

    HookEvent("versus_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

/**
 * Called when a console variable value is changed.
 *
 * @param convar       Handle to the convar that was changed
 * @param oldValue     String containing the value of the convar before it was changed
 * @param newValue     String containing the new value of the convar
 * @noreturn
 */
void OnGamemodeChanged(ConVar convar, const char[] sOldGameMode, const char[] sNewGameMode) {
    g_bGamemodeAvailable = IsVersusMode(sNewGameMode);
}

/**
 * Round start event.
 */
void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bGamemodeAvailable) {
        return;
    }

    CreateTimer(1.0, Timer_RoundStart, _, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer for switch team.
 */
 Action Timer_RoundStart(Handle timer)
 {
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IS_REAL_CLIENT(iClient) || !IS_SPECTATOR(iClient)) {
            continue;
        }

        RespectateClient(iClient);
    }

    return Plugin_Handled;
 }

/**
 * A hack that switches the player to the infected team and back to the observers.
 */
void RespectateClient(int iClient)
{
    ChangeClientTeam(iClient, TEAM_INFECTED);
    CreateTimer(0.1, Timer_TurnClientToSpectate, iClient, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer for switch team.
 */
Action Timer_TurnClientToSpectate(Handle timer, int iClient)
{
    if (IS_REAL_CLIENT(iClient)) {
        ChangeClientTeam(iClient, TEAM_SPECTATOR);
    }

    return Plugin_Handled;
}

/**
 * Is the game mode versus.
 *
 * @param szGameMode     A string containing the name of the game mode
 *
 * @return              Returns true if verus, otherwise false
 */
bool IsVersusMode(const char[] szGameMode) {
    return (StrEqual(szGameMode, GAMEMODE_VERSUS, false) || StrEqual(szGameMode, GAMEMODE_VERSUS_REALISM, false));
}
