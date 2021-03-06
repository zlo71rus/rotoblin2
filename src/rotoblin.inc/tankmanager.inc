/*
 * ============================================================================
 *
 *  Rotoblin
 *
 *  File:			tankmanager.inc
 *  Type:			Helper
 *  Description:	Keep track of the current tank player
 *
 *  Copyright (C) 2012-2015  raziEiL <war4291@mail.ru>
 *  Copyright (C) 2010  Mr. Zero <mrzerodk@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ============================================================================
 */

// Don't let the script be included more than once.
#if defined _helper_tankmgr
  #endinput
#endif
#define _helper_tankmgr

// --------------------
//       Private
// --------------------
static					g_iTankClient			= 0;					// Which client is currently playing as tank
static			bool:	g_bIsTankInPlay			= false;				// Whether or not the tank is active
static					g_iDebugChannel			= 0;
static	const	String:	DEBUG_CHANNEL_NAME[]	= "TankManager";

// **********************************************
//                 Forwards
// **********************************************

/**
 * On plugin start.
 *
 * @noreturn
 */
_H_TankManager_OnPluginStart()
{
	g_iDebugChannel = DebugAddChannel(DEBUG_CHANNEL_NAME);
	DebugPrintToAllEx("Module is now setup");
}

/**
 * On plugin enabled.
 *
 * @noreturn
 */
_H_TM_OnPluginEnabled()
{
	HookEvent("tank_spawn", _H_TM_TankSpawn_Event);
	HookEvent("player_death", _H_TM_TankKilled_Event);
	HookEvent("round_start", _H_TM_RoundStart_Event);
	H_TM_ResetVars();

	DebugPrintToAllEx("Module is now loaded");
}

/**
 * On plugin disabled.
 *
 * @noreturn
 */
_H_TM_OnPluginDisabled()
{
	UnhookEvent("tank_spawn", _H_TM_TankSpawn_Event);
	UnhookEvent("player_death", _H_TM_TankKilled_Event);
	UnhookEvent("round_start", _H_TM_RoundStart_Event);
	H_TM_ResetVars();

	DebugPrintToAllEx("Module is now unloaded");
}

H_TM_ResetVars()
{
	g_bIsTankInPlay = false;
	g_iTankClient = 0;
}

/**
 * Player disconnected.
 *
 * @param client		Client index that disconnected.
 * @noreturn
 */
_H_TM_OnClientDisconnect_Post(client)
{
	if (!g_bIsTankInPlay || client != g_iTankClient) return; // If the tank isn't in play or not the disconnecting player, return
	DebugPrintToAllEx("Tank client left the game, find new tank client");
	CreateTimer(0.1, _H_TM_TankKilled_Timer, client); // Use a delay'd timer due to bugs where the tank passes to another player
}

/**
 * Called when round start event is fired.
 *
 * @param event			Handle to event.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @noreturn
 */
public _H_TM_RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	DebugPrintToAllEx("Round start; reset vars");
	g_bIsTankInPlay = false;
}

/**
 * Called when tank spawn event is fired.
 *
 * @param event			Handle to event.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @noreturn
 *
 * @remarks				Gets triggered when passed to player FROM AI or TO AI from
 *						player. It is NOT triggered when passed to player FROM PLAYER.
 */
public _H_TM_TankSpawn_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_iTankClient = client;

	if (g_bIsTankInPlay)
	{
		DebugPrintToAllEx("Tank spawned, updated tank client var. Client %i: \"%N\"", client, client);

		Global_ev_OnTankPassed();
		return; // If tank is already in play (passed to another player), return
	}
	DebugPrintToAllEx("Tank spawned, tank is now in play. Client %i: \"%N\"", client, client);
	g_bIsTankInPlay = true;

	Global_ev_OnTankSpawn();
}

/**
 * Called when tank killed event is fired.
 *
 * @param event			Handle to event.
 * @param name			String containing the name of the event.
 * @param dontBroadcast	True if event was not broadcast to clients, false otherwise.
 * @noreturn
 *
 * @remarks				This event is not the tank_killed event, but in fact the
 *						player_death event. Reason for this, is because tank_killed
 *						event in finale seems broken. Gets randomly executed or
 *						sometimes, not at all.
 *						This gets triggered upon each time ANY client loose control of
 *						tank. Including AI or player passing control, or player lost
 *						control.
 */
public _H_TM_TankKilled_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bIsTankInPlay) return; // If the tank isn't in play, return

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client != g_iTankClient) return; // If tank client wasn't the dieing client, return
	DebugPrintToAllEx("Tank was killed, find new tank client. Client %i: \"%N\"", client, client);

	CreateTimer(0.1, _H_TM_TankKilled_Timer, client); // Use a delay'd timer due to bugs where the tank passes to another player
}

/**
 * Called when the tank killed timer interval has elapsed.
 *
 * @param timer			Handle to the timer object.
 * @param oldtankclient	The client that was playing as tank before.
 * @noreturn
 */
public Action:_H_TM_TankKilled_Timer(Handle:timer, any:oldtankclient)
{
	if (g_iTankClient != oldtankclient) return; // If the tank client var have been changed (tank have been passed), return

	new tankclient = FindTankClient();
	if (tankclient && tankclient != oldtankclient)
	{
		g_iTankClient = tankclient; // Set tank client
		DebugPrintToAllEx("Found new tank client. Client %i: \"%N\"", tankclient, tankclient);

		Global_ev_OnTankPassed();
		return; // Found tank, return
	}

	DebugPrintToAllEx("Tank was killed and is no longer in play. Forward event");
	g_bIsTankInPlay = false; // No tank in play

	Global_ev_OnTankKilled();
}

// **********************************************
//                 Public API
// **********************************************

/**
 * Returns which client is currently the tank.
 *
 * @return				Client that are currently in control of the tank or 0 if no tank is in play.
 */
stock GetTankClient()
{
	if (!g_bIsTankInPlay) return 0;

	new tankclient = g_iTankClient;

	if (!IsClientInGame(tankclient)) // If tank somehow is no longer in the game (kicked, hence events didn't fire)
	{
		tankclient = FindTankClient(); // find the tank client
		if (!tankclient) return 0;
		g_iTankClient = tankclient;
	}

	return tankclient;
}

/**
 * Returns how much frustration tank currently have, in percentage.
 *
 * @return				How much frustration tank have left in percentage, -1 if tank is not active.
 */
stock GetTankPrecentFrustration()
{
	new tankclient = GetTankClient();
	if (!tankclient) return -1;

	return (100 - GetFrustration(tankclient));
}


stock GetPrecentFrustration(tankclient)
{
	if (!tankclient) return -1;

	return (100 - GetFrustration(tankclient));
}

/**
 * Returns true if tank is incapacitated, also known as "dying" animation.
 * Don't rely on this function for capturing death event of the tank. The incap
 * animation seems to be played upon some conditions and sometimes not at all.
 *
 * @return				True if tank is incapacitated / dying, false otherwise.
 */
stock bool:IsTankDying()
{
	new tankclient = GetTankClient();
	if (!tankclient) return false;

	return bool:IsIncapacitated(tankclient);
}

/**
 * Returns true if tank has been lit.
 *
 * @return				True if tank is on fire, false otherwise.
 */
stock bool:IsTankOnFire()
{
	new tankclient = GetTankClient();
	if (!tankclient) return false;

	return bool:(GetEntityFlags(tankclient) & FL_ONFIRE);
}

stock bool:IsClientOnFire(client)
{
	return bool:(GetEntityFlags(client) & FL_ONFIRE);
}

/**
 * Returns whether the tank is in play.
 *
 * @return				True if tank is in play, false otherwise.
 */
stock bool:IsTankInPlay()
{
	return g_bIsTankInPlay;
}

// **********************************************
//                 Private API
// **********************************************

/**
 * Finds the current tank client.
 *
 * @return				Client index currently playing as tank, 0 if no tank
 *						found.
 */
public FindTankClient()
{
	for (new i = 0; i < InfectedCount; i++)
	{
		if (InfectedIndex[i] <= 0 || !IsClientInGame(InfectedIndex[i]) || !IsInfectedAlive(InfectedIndex[i]) || !IsPlayerTank(InfectedIndex[i]) || IsIncapacitated(InfectedIndex[i])) continue;

		return InfectedIndex[i];
	}
	return 0;
}

/**
 * Wrapper for printing a debug message without having to define channel index
 * everytime.
 *
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @noreturn
 */
static DebugPrintToAllEx(const String:format[], any:...)
{
	decl String:buffer[DEBUG_MESSAGE_LENGTH];
	VFormat(buffer, sizeof(buffer), format, 2);
	DebugPrintToAll(g_iDebugChannel, buffer);
}