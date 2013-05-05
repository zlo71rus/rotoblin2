/*
 * ============================================================================
 *
 * This file is part of the Rotoblin 2 project.
 *
 *  File:			rotoblin.WitchesTracking.sp
 *  Type:			Module
 *  Description:	Enables forcing same coordinates for witch spawns.
 *
 *  Copyright (C) 2012-2013 raziEiL <war4291@mail.ru>
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

#define		WT_TAG					"[WitchesTracking]"

#define WITCH_TO_CLOSE				300

static	Handle:g_hWitchArray, Handle:g_hMaxWitches, g_iCvarMaxWithes, bool:g_bFirstRound, g_iWitchCount, g_iSpawnedWitches;

public _WitchTracking_OnPluginStart()
{
	g_hMaxWitches = CreateConVarEx("max_witches", "0", "Max number of Witches are allowed to spawn.", _, true, 0.0);
	g_hWitchArray = CreateArray(3);
}

_WT_OnPluginEnabled()
{
	HookConVarChange(g_hMaxWitches,	_WT_MaxWitches_CvarChange);

	HookEvent("round_start", WT_ev_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("witch_spawn", WT_ev_WitchSpawn);
	Update_WT_MaxWithesConVar();
}

_WT_OnPluginDisabled()
{
	UnhookConVarChange(g_hMaxWitches,	_WT_MaxWitches_CvarChange);

	UnhookEvent("round_start", WT_ev_RoundStart, EventHookMode_PostNoCopy);
	UnhookEvent("witch_spawn", WT_ev_WitchSpawn);
	_WT_OnMapEnd();
}

_WT_OnMapEnd()
{
	g_bFirstRound = false;
	ClearArray(g_hWitchArray);
}

public Action:WT_ev_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bFirstRound = !g_bFirstRound;
	g_iWitchCount = 0;

	DebugLog("%s ==== ROUND %d FIRED ====", WT_TAG, g_bFirstRound);

	if (!g_bFirstRound)
		CreateTimer(3.0, WT_t_SpawnWitch);
}

public Action:WT_t_SpawnWitch(Handle:timer)
{
	new iArrayLimit = GetArraySize(g_hWitchArray);
	if (!iArrayLimit) return;

	g_iSpawnedWitches = iArrayLimit / 2;

	UnhookEvent("witch_spawn", WT_ev_WitchSpawn);

	decl Float:fWitchData[2][3];
	new iEnt = -1;

	for (new i = 0; i < iArrayLimit; i += 2){

		GetArrayArray(g_hWitchArray, i, fWitchData[0]);
		GetArrayArray(g_hWitchArray, i + 1, fWitchData[1]);

		iEnt = CreateEntityByName("witch");
		TeleportEntity(iEnt, fWitchData[0], fWitchData[1], NULL_VECTOR);
		DispatchSpawn(iEnt);

		DebugLog("%s Restore Witch %d at %f %f %f ", WT_TAG, iEnt, fWitchData[0][0], fWitchData[0][1], fWitchData[0][2]);
	}

	HookEvent("witch_spawn", WT_ev_WitchSpawn);
}

public Action:WT_ev_WitchSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new iEnt = GetEventInt(event, "witchid");

	decl Float:fWitchData[2][3];
	GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fWitchData[0]);

	if (IsWitchesTooClose(fWitchData[0]) || (g_iCvarMaxWithes && ++g_iWitchCount > g_iCvarMaxWithes)){

		DebugLog("%s Round %s Witch %d was removed. Limit is exceeded, or too close! (Limit %d/%d)", WT_TAG, g_bFirstRound ? "1" : "2", iEnt, g_iWitchCount, g_iCvarMaxWithes);
		AcceptEntityInput(iEnt, "Kill");
		return;
	}

	if (!g_bFirstRound){

		if (g_iSpawnedWitches-- > 0){

			DebugLog("%s Round 2 Valve Witch %d was removed %.2f %.2f %.2f (Should be removed: %d)", WT_TAG, iEnt, fWitchData[0][0], fWitchData[0][1], fWitchData[0][2], g_iSpawnedWitches);
			AcceptEntityInput(iEnt, "Kill");
			return;
		}

		DebugLog("%s Round 2 Dont remove this Witch %d (First team died before this witch was spawn in round1)", WT_TAG, iEnt);
	}
	
	GetEntPropVector(iEnt, Prop_Send, "m_angRotation", fWitchData[1]);
	PushArrayArray(g_hWitchArray, fWitchData[0]);
	PushArrayArray(g_hWitchArray, fWitchData[1]);

	DebugLog("%s Round %s Push Witch %d in array %.2f %.2f %.2f (Total: %d)", WT_TAG, g_bFirstRound ? "1" : "2", iEnt, fWitchData[0][0], fWitchData[0][1], fWitchData[0][2], g_iWitchCount);
}

static bool:IsWitchesTooClose(Float:vOrg[3])
{
	decl iArrayLimit;
	if (!(iArrayLimit = GetArraySize(g_hWitchArray)))
		return false;

	decl Float:fDataOrg[3];

	for (new i = 0; i < iArrayLimit; i += 2){

		GetArrayArray(g_hWitchArray, i, fDataOrg);

		if ((fDataOrg[0] = GetVectorDistance(vOrg, fDataOrg)) < WITCH_TO_CLOSE){

			DebugLog("%s Withes to close %.0f!", WT_TAG, fDataOrg[0]);
			return true;
		}
	}

	return false;
}

bool:FirstRound()
{
	return g_bFirstRound;
}

public _WT_MaxWitches_CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
		Update_WT_MaxWithesConVar();
}

static Update_WT_MaxWithesConVar()
{
	g_iCvarMaxWithes = GetConVarInt(g_hMaxWitches);
}

stock _WT_CvarDump()
{
	decl iVal;
	if ((iVal = GetConVarInt(g_hMaxWitches)) != g_iCvarMaxWithes)
		DebugLog("%d		|	%d		|	rotoblin_max_witches", iVal, g_iCvarMaxWithes);
}
