#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <l4d_lib>

#define MAX(%0,%1) (((%0) > (%1)) ? (%0) : (%1))

#define STR_MAX_WEAPON_LEN      32

#define SHOTGUN_TIME            0.25
#define MELEE_TIME              0.25
#define POUNCE_TIMER            0.1

#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define HITGROUP_HEAD           1

#define BREV_SI                 1
#define BREV_CI                 2
#define BREV_ACC                4
#define BREV_SKEET              8

#define BREV_MELEE              32
#define BREV_DMG                64


// zombie classes
#define ZC_SMOKER               1
#define ZC_BOOMER               2
#define ZC_HUNTER               3
#define ZC_TANK                 5

// weapon types
#define WPTYPE_NONE             0
#define WPTYPE_SHELLS           1
#define WPTYPE_MELEE            2
#define WPTYPE_BULLETS          3

// weapons
#define WP_MELEE                19

#define WP_PISTOL               1
#define WP_SMG                  2
#define WP_HUNTING_RIFLE        6
#define WP_PUMPSHOTGUN          3
#define WP_AUTOSHOTGUN          4
#define WP_RIFLE                5

// damage type
#define DMG_CRUSH               (1 << 0)        // crushed by falling or moving object.
#define DMG_BULLET              (1 << 1)        // shot
#define DMG_SLASH               (1 << 2)        // cut, clawed, stabbed
#define DMG_CLUB                (1 << 7)        // crowbar, punch, headbutt
#define DMG_BUCKSHOT            (1 << 29)       // not quite a bullet. Little, rounder, different.

/*
        Changelog
        ---------

            0.1f
                - fixed more error spam in error logs
            0.1e
                - fixed error spam in error logs
            0.1d
                - melee accuracy now hidden by default
                - built in some better safeguards against client index out of bounds probs
 */


public Plugin:myinfo =
{
    name = "[L4D] 1v1 SkeetStats",
    author = "Tabun, raziEiL [diswar1]",
    description = "Shows 1v1-relevant info at end of round.",
    version = "0.3 beta",
    url = "nope"
};

new Handle: hCountTankDamage =  INVALID_HANDLE;         // whether we're tracking tank damage
new Handle: hCountWitchDamage = INVALID_HANDLE;         // whether we're tracking witch damage
new Handle: hBrevityFlags =     INVALID_HANDLE;         // how verbose/brief the output should be:
/*
        1       leave out Kill stats
        2       leave out CI stats
        4       leave out Accuracy stats
        8       leave out Skeet stats
        32      leave out Melee accuracy
        64      leave out Damage count
*/
new bool: bCountTankDamage;
new bool: bCountWitchDamage;
new iBrevityFlags;

new String: sClientName[MAXPLAYERS + 1][64];    // which name is connected to the clientId?

new iGotKills[MAXPLAYERS + 1];                  // SI kills             track for each client
new iGotCommon[MAXPLAYERS + 1];                 // CI kills
new iDidDamage[MAXPLAYERS + 1];                 // SI only              these are a bit redundant, but will keep anyway for now
new iDidDamageAll[MAXPLAYERS + 1];              // SI + tank + witch
new iDidDamageTank[MAXPLAYERS + 1];             // tank only
new iDidDamageWitch[MAXPLAYERS + 1];            // witch only

new iShotsFired[MAXPLAYERS + 1];                // shots total
new iPelletsFired[MAXPLAYERS + 1];              // shotgun pellets total
new iShotsHit[MAXPLAYERS + 1];                  // shots hit
new iPelletsHit[MAXPLAYERS + 1];                // shotgun pellets hit
new iMeleesFired[MAXPLAYERS + 1];               // melees total
new iMeleesHit[MAXPLAYERS + 1];                 // melees hit

new iDeadStops[MAXPLAYERS + 1];                 // all hunter deadstops (lunging hunters only)
new iHuntSkeets[MAXPLAYERS + 1];                // actual skeets (lunging hunter kills, full/normal)
new iHuntSkeetsInj[MAXPLAYERS + 1];             // injured skeets (< 150.0, on injured hunters)
new iHuntHeadShots[MAXPLAYERS + 1];             // all headshots on hunters (non-skeets too)

new bool: bIsHurt[MAXPLAYERS + 1];              // if a hunter player has been damaged (below 150)
new bool: bIsPouncing[MAXPLAYERS + 1];          // if a hunter player is currently pouncing
new iDmgDuringPounce[MAXPLAYERS + 1];           // how much total damage in a single pounce (cumulative)

new iClientPlaying;                             // which clientId is the survivor this round?
new iRoundNumber;
new bool: bInRound;
new bool: bPlayerLeftStartArea;                 // used for tracking FF when RUP enabled

new Float: fPreviousShot[MAXPLAYERS + 1];       // when was the previous shotgun blast? (to collect all hits for 1 shot)
new iPreviousShotType[MAXPLAYERS + 1];          // weapon id for shotgun/melee that fired previous shot
new bCurrentShotHit[MAXPLAYERS + 1];            // whether we got a hit for the shot
new iCurrentShotDmg[MAXPLAYERS + 1];            // counting shotgun blast damage
/*
new bCurrentShotSkeet[MAXPLAYERS + 1];          // whether we got a full skeet with the shot
new bCurrentShotSkeetInj[MAXPLAYERS + 1];       // whether we got an injured skeet with the shot
*/

/*
 *      init
 *      ====
 */

public OnPluginStart()
{
    HookEvent("round_start", RoundStart_Event, EventHookMode_PostNoCopy);
    HookEvent("round_end", RoundEnd_Event, EventHookMode_PostNoCopy);
    HookEvent("player_left_start_area", PlayerLeftStartArea);

    // Catching data
    HookEvent("player_hurt", PlayerHurt_Event, EventHookMode_Post);
    HookEvent("player_death", PlayerDeath_Event, EventHookMode_Post);
    HookEvent("player_shoved", PlayerShoved_Event, EventHookMode_Post);
    HookEvent("infected_hurt" ,InfectedHurt_Event, EventHookMode_Post);
    HookEvent("infected_death", InfectedDeath_Event, EventHookMode_Post);

    HookEvent("weapon_fire", WeaponFire_Event, EventHookMode_Post);
    HookEvent("ability_use", AbilityUse_Event, EventHookMode_Post);

    // Cvars
    hCountTankDamage =  CreateConVar("sm_skeetstat_counttank",    "0",  "Damage on tank counts towards totals if enabled.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
    hCountWitchDamage = CreateConVar("sm_skeetstat_countwitch",   "0",  "Damage on witch counts towards totals if enabled.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
    hBrevityFlags =     CreateConVar("sm_skeetstat_brevity",     "32",  "Flags for setting brevity of the report (hide 1:SI, 2:CI, 4:Accuracy, 8:Skeets/Deadstops, 32: melee acc, 64: damage count).", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0);

    bCountTankDamage =  GetConVarBool(hCountTankDamage);
    bCountWitchDamage = GetConVarBool(hCountWitchDamage);
    iBrevityFlags =     GetConVarInt(hBrevityFlags);

    HookConVarChange(hCountTankDamage, ConVarChange_CountTankDamage);
    HookConVarChange(hCountWitchDamage, ConVarChange_CountWitchDamage);
    HookConVarChange(hBrevityFlags, ConVarChange_BrevityFlags);

    bPlayerLeftStartArea = false;

    // Commands
    RegConsoleCmd("sm_skeets", SkeetStat_Cmd, "Prints the current skeetstats.");

    RegConsoleCmd("say", Say_Cmd);
    RegConsoleCmd("say_team", Say_Cmd);

    // late loading
    if (g_bLoadLater) {
        bPlayerLeftStartArea = true;            // assume they left it
        iClientPlaying = GetCurrentSurvivor();  // find survivor again
    }
}

/*
public OnPluginEnd()
{
    // nothing
}
*/

public OnClientPutInServer(client)
{
    decl String:tmpBuffer[64];
    GetClientName(client, tmpBuffer, sizeof(tmpBuffer));

    // if previously stored name for same client is not the same, delete stats & overwrite name
    if (strcmp(tmpBuffer, sClientName[client], true) != 0)
    {
        ClearClientSkeetStats(client);

        // store name for later reference
        strcopy(sClientName[client], 64, tmpBuffer);
    }
}

/*
 *      convar changes  (phase this out later)
 *      ==============
 */

public ConVarChange_CountTankDamage(Handle:cvar, const String:oldValue[], const String:newValue[])      { if (StringToInt(newValue) == 0) { bCountTankDamage = false; } else { bCountTankDamage = true; } }
public ConVarChange_CountWitchDamage(Handle:cvar, const String:oldValue[], const String:newValue[])     { if (StringToInt(newValue) == 0) { bCountWitchDamage = false; } else { bCountWitchDamage = true; } }
public ConVarChange_BrevityFlags(Handle:cvar, const String:oldValue[], const String:newValue[])         { iBrevityFlags = StringToInt(newValue); }

/*
 *      map load / round start/end
 *      ==========================
 */

public Action:PlayerLeftStartArea(Handle:event, const String:name[], bool:dontBroadcast)
{
    iClientPlaying = GetCurrentSurvivor();
    bPlayerLeftStartArea = true;                        // if RUP active, now we can start tracking
}

public OnMapStart()
{
    if (!g_bLoadLater)                                     // apparently mapstart gets called even after.. it has already started
    {
        bPlayerLeftStartArea = false;
    }
    g_bLoadLater = false;                                  // make sure leftstartarea gets reset after a lateload
}

public OnMapEnd()
{
    iRoundNumber = 0;
    bInRound = false;
}

public RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    iClientPlaying = GetCurrentSurvivor();
    bPlayerLeftStartArea = false;

    if (!bInRound)
    {
        bInRound = true;
        iRoundNumber++;
    }

    // clear mvp stats
    new i, maxplayers = MaxClients;
    for (i = 1; i <= maxplayers; i++)
    {
        ClearClientSkeetStats(i);
    }
}

public RoundEnd_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    // only show / log stuff when the round is done "the first time"
    if (bInRound)
    {
        ResolveOpenShots();                             // just in case there are any shots opened.
        CreateTimer(3.0, delayedSkeetStatPrint);
        bInRound = false;
    }
}


/*
 *      cmds / reports
 *      ==============
 */

public Action:Say_Cmd(client, args)
{
    if (!client) { return Plugin_Continue; }
    decl String:sMessage[MAX_NAME_LENGTH];
    GetCmdArg(1, sMessage, sizeof(sMessage));

    if (StrEqual(sMessage, "!skeets")) { return Plugin_Handled; }

    return Plugin_Continue;
}

public Action:SkeetStat_Cmd(client, args)
{
    //FloatSub(GetEngineTime(), fPreviousShot[user]) < SHOTGUN_TIME             // <-- use this to avoid the following from affecting stats.. maybe.
    ResolveOpenShots();                                 // make sure we're up to date (this *might* affect the stats, but it'd have to be insanely badly timed
    PrintSkeetStats(client);
    return Plugin_Handled;
}

public Action:delayedSkeetStatPrint(Handle:timer)
{
    PrintSkeetStats(0);
}



/*
 *      track damage/kills & accuracy
 *      =============================
 */
static g_iDmgToHunter[MAXPLAYERS+1];

public PlayerHurt_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player

    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

    if (attacker != iClientPlaying)                             { return; }     // ignore shots fired by anyone but survivor player
    if (GetClientTeam(victim) != TEAM_INFECTED)                 { return; }     // safeguard

    new damage =        GetEventInt(event, "dmg_health");
    new damagetype =    GetEventInt(event, "type");
    new hitgroup =      GetEventInt(event, "hitgroup");

    // accuracy track
    if (damagetype & DMG_BUCKSHOT) {

        // this is still part of the (previous) shotgun blast
        iCurrentShotDmg[iClientPlaying] += damage;

        // are we skeeting hunters?
        if (bIsPouncing[victim]){

            iDmgDuringPounce[victim] += damage;
            //PrintToChatAll("[test] pounce/SG dmg: %d (total: %d / duringpounce: %d / remain: %d)", damage, iCurrentShotDmg[iClientPlaying], iDmgDuringPounce[victim], health);

            // skeet or hurt
            if (!g_iDmgToHunter[victim])
                CreateTimer(0.1, SS_t_ResetTotalDmg, victim);

            g_iDmgToHunter[victim] += damage;
            CheckHurtDmg(victim);
            // ----------
        }
        if (!bCurrentShotHit[iClientPlaying]) {
            if (hitgroup == HITGROUP_HEAD) { iHuntHeadShots[iClientPlaying]++; }              // only count headshot once for shotgun blast (not that it matters, but this might miss some hs's)
        }

        bCurrentShotHit[iClientPlaying] = true;
    }
    else if (damagetype & DMG_BULLET) {
        // for bullets, simply count all hits
        iShotsHit[iClientPlaying]++;
        if (hitgroup == HITGROUP_HEAD) { iHuntHeadShots[iClientPlaying]++; }

        // are we skeeting hunters?
        if (bIsPouncing[victim]) {
            iDmgDuringPounce[victim] += damage;
            //PrintToChatAll("[test] pounce/BUL dmg: %d (duringpounce: %d / remain: %d)", damage, iDmgDuringPounce[victim], health);
        }
    }
    else if (damagetype & DMG_SLASH || damagetype & DMG_CLUB) {
        // for melees, like shotgun (multiple hits for one, so just count once)
        if (iPreviousShotType[iClientPlaying] == WP_MELEE && FloatSub(GetEngineTime(), fPreviousShot[iClientPlaying]) < MELEE_TIME) {
            bCurrentShotHit[iClientPlaying] = true;
        }
    }

    // track damage
    // separately store SI and tank damage
    if (!IsPlayerTank(victim))
    {
        iDidDamage[attacker] += damage;
        iDidDamageAll[attacker] += damage;
    }
    else if (bCountTankDamage)
    {
        iDidDamageAll[attacker] += damage;
        iDidDamageTank[attacker] += damage;
    }
}

CheckHurtDmg(victim)
{
    if (g_iDmgToHunter[victim] < 250)
        bIsHurt[victim] = true;
    else
        bIsHurt[victim] = false;
}

public Action:SS_t_ResetTotalDmg(Handle:timer, any:victim)
{
    CheckHurtDmg(victim);
    g_iDmgToHunter[victim] = 0;
}

public InfectedHurt_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player

    // check user
    new user = GetClientOfUserId(GetEventInt(event, "attacker"));
    if (user != iClientPlaying)                                 { return; }     // ignore shots fired by anyone but survivor player

    // check if round started
    if (!bPlayerLeftStartArea)                                  { return; }     // don't count saferoom shooting for now.

    new damage = GetEventInt(event, "amount");
    new damageType = GetEventInt(event, "type");
    new victimEntId = GetEventInt(event, "entityid");

    // accuracy track


    //-- test -------------------------------------
    /*
    //decl String: weapon[STR_MAX_WEAPON_LEN];
    //GetClientWeapon(user, weapon, sizeof(weapon));
    //new weaponId = WeaponNameToId(weapon);
    //new weaponType = GetWeaponType(weaponId);
    decl String: tmp[STR_MAX_WEAPON_LEN];
    if (damageType & DMG_BULLET) { tmp = "bullet"; }
    if (damageType & DMG_SLASH) { tmp = "slash"; }
    if (damageType & DMG_CLUB) { tmp = "club"; }
    if (damageType & DMG_BUCKSHOT) { tmp = "buckshot"; }
    PrintToChatAll("InfHurt WP: %s [%d] - dmg: %d / type: %s", weapon, WeaponNameToId(weapon), damage, tmp);
    */
    //-- test -------------------------------------

    // shotgun
    if (damageType & DMG_BUCKSHOT) {
        //if (FloatSub(GetEngineTime(), fPreviousShot[user]) < SHOTGUN_TIME) { // don't do this for now, open/close shotgun is otherwise resolved

        // this is still part of the (previous) shotgun blast
        bCurrentShotHit[iClientPlaying] = true;
        if (IsCommonInfected(victimEntId)) {
            switch (iPreviousShotType[iClientPlaying]) {
                    case WP_PUMPSHOTGUN:    { damage = RoundFloat(float(damage) * 2.03); }       // max 123 on common (250)
                    case WP_AUTOSHOTGUN:    { damage = RoundFloat(float(damage) * 2.29); }       // max 113 on common (253)
                }
        }
        else if (IsWitch(victimEntId)) {
            new damageDone = damage;

            // event called per pellet
            switch (iPreviousShotType[iClientPlaying]) {
                case WP_PUMPSHOTGUN:    { damage = 25; }
                case WP_AUTOSHOTGUN:    { damage = 25; }
            }
            // also note that crowns do 1 pellet damage less than actual, for some reason, so add it:
            //          each pellet doing > 100 means close enough to the crown
            if (iCurrentShotDmg[iClientPlaying] + damage > 200 && damageDone > 100) { damage = damage * 2; }
        }
        iCurrentShotDmg[iClientPlaying] += damage;
    }
    else if (damageType & DMG_BULLET) {
        // for bullets, simply count all hits
        iShotsHit[iClientPlaying]++;
    }
    else if (damageType & DMG_SLASH || damageType & DMG_CLUB) {
        // for melees, like shotgun (multiple hits for one, so just count once)
        if (iPreviousShotType[iClientPlaying] == WP_MELEE && FloatSub(GetEngineTime(), fPreviousShot[iClientPlaying]) < MELEE_TIME) {
            bCurrentShotHit[iClientPlaying] = true;
        }
    }

    // witch (damage)
    if (IsWitch(victimEntId))
    {
        new damageDone = GetEventInt(event, "amount");

        // no world damage or flukes or whatevs, no bot attackers
        if (bCountWitchDamage)
        {
            iDidDamageAll[user] += damageDone;
            iDidDamageWitch[user] += damageDone;
        }
    }
}

public PlayerDeath_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

    if (attacker != iClientPlaying)                             { return; }     // ignore shots fired by anyone but survivor player
    if (!IsClientAndInGame(victim))                             { return; }     // safeguard
    if (GetClientTeam(victim) != TEAM_INFECTED)                 { return; }     // safeguard

    new damagetype = GetEventInt(event, "type");

    // skeet check
    if (damagetype & DMG_BUCKSHOT || damagetype & DMG_BULLET) {
        // shotgun

        //PrintToChatAll("[test] death: (pounce: %d, abort: %d, ishurt: %d, total dmg: %d / duringpounce: %d)", bIsPouncing[victim], GetEventBool(event, "abort"), bIsHurt[victim], iCurrentShotDmg[iClientPlaying], iDmgDuringPounce[victim]);

        // did we skeet a hunter?
        if (bIsPouncing[victim]){

            if (bIsHurt[victim])             // inj. skeet
                iHuntSkeetsInj[iClientPlaying]++;
            else                            // normal/full skeet
                iHuntSkeets[iClientPlaying]++;

       }
    }

    // reset
    bIsHurt[victim] = false;
    bIsPouncing[victim] = false;
    iDmgDuringPounce[victim] = 0;

    // only SI, not the tank && only player-attackers
    if (!IsPlayerTank(victim))
    {
        // store kill to count for attacker id
        iGotKills[attacker]++;
    }
}

public InfectedDeath_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player;
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

    if (IsClientAndInGame(attacker))
    {
        if ((GetClientTeam(attacker) == TEAM_SURVIVOR)) {
            iGotCommon[attacker]++;
        }
    }
}

public PlayerShoved_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player
    // check user
    new user = GetClientOfUserId(GetEventInt(event, "attacker"));
    if (user != iClientPlaying)                                 { return; }     // ignore actions by anyone else

    // get hunter player
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));

    if (bIsPouncing[victim] && IsInfected(victim) && GetPlayerClass(victim) == ZC_HUNTER)
    {
        iDeadStops[user]++;
        bIsPouncing[victim] = false;
        iDmgDuringPounce[victim] = 0;
    }
}

// hunters pouncing / tracking
public AbilityUse_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player
    // track hunters pouncing
    new user = GetClientOfUserId(GetEventInt(event, "userid"));

    if (IsClientAndInGame(user) && !bIsPouncing[user]){

        decl String:abilityName[64];
        GetEventString(event,"ability",abilityName,sizeof(abilityName));

        if (strcmp(abilityName,"ability_lunge",false) == 0)
        {
            // Hunter pounce
            bIsPouncing[user] = true;
            iDmgDuringPounce[user] = 0;                                     // use this to track skeet-damage
            CreateTimer(POUNCE_TIMER,groundTouchTimer,user,TIMER_REPEAT);   // check every TIMER whether the pounce has ended
        }
    }
}

public Action:groundTouchTimer(Handle:timer, any:client)
{
    if(IsClientAndInGame(client) && (isGrounded(client) || !IsPlayerAlive(client)))
    {
        // Reached the ground or died in mid-air
        bIsPouncing[client] = false;
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public bool:isGrounded(client)
{
    return (GetEntProp(client,Prop_Data,"m_fFlags") & FL_ONGROUND) > 0;
}

// accuracy:
public WeaponFire_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (IsRupEnable()) { return; }     // ignore any shots by RUP-frozen player
    // check user
    new user = GetClientOfUserId(GetEventInt(event, "userid"));
    if (user != iClientPlaying)                                 { return; }     // ignore shots fired by anyone but survivor player

    // check if round started
    if (!bPlayerLeftStartArea)                                  { return; }     // don't count saferoom shooting for now.

    new weaponId = GetEventInt(event, "weaponid");
    new count = GetEventInt(event, "count");

    //-- test -------------------------------------
    /*
    decl String:weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    PrintToChatAll("WF: %s [%d] - cnt: %d .", weapon, weaponId, count);
    */
    //-- test -------------------------------------

    // differentiate between weapon types
    new weaponType = GetWeaponType(weaponId);

    // 1. shotgun blasts (keep track of pellets, separate shot accuracy from pellet accuracy
    if (weaponType == WPTYPE_SHELLS)
    {
        // handle previous shot, if any open
        ResolveOpenShots();

        // open new shot
        iShotsFired[iClientPlaying]++;
        iPelletsFired[iClientPlaying] += count;
        fPreviousShot[iClientPlaying] = GetEngineTime();        // track shot from this time
        bCurrentShotHit[iClientPlaying] = false;                // so we can check just 1 hit for the shot
        iCurrentShotDmg[iClientPlaying] = 0;                    // reset, count damage for this shot
        iPreviousShotType[iClientPlaying] = weaponId;           // so we know what kind of shotgun blast it was
        return;
    }

    // 2. melee
    if (weaponType == WPTYPE_MELEE)
    {
        // handle previous shot, if any open
        ResolveOpenShots();

        iMeleesFired[iClientPlaying]++;
        fPreviousShot[iClientPlaying] = GetEngineTime();        // track shot from this time
        bCurrentShotHit[iClientPlaying] = false;                // so we can check just 1 hit for the swing
        iCurrentShotDmg[iClientPlaying] = 0;                    // reset, count damage for this shot
        iPreviousShotType[iClientPlaying] = WP_MELEE;           // so we know a melee is 'out'
        return;
    }

    // 3. rifles / snipers / pistols (per shot accuracy)
    if (weaponType == WPTYPE_BULLETS)
    {
        iShotsFired[iClientPlaying]++;
        return;
    }

    // 4. weird cases: pain pills / medkits
    // not relevant, ignore for now
}


/*
 *      Stat string
 *      ======================
 */

String: PrintSkeetStats(toClient)
{
    decl String:printBuffer[512];
    decl String:tmpBuffer[256];

    printBuffer = "";

    if (iClientPlaying <= 0) { return; }

    /*
    //decl String:tmpName[64];
    if (!IsClientConnected(iClientPlaying)) {
        tmpName = sClientName[iClientPlaying];
    } else {
        Format(tmpName, sizeof(tmpName),"%N", iClientPlaying);
    } */

    // no need to calculate, show stats
    //  1. SI damage & SI kills
    //  2. skeets
    //  3. accuracy
    //  4. common kills

    /*
        TODO: make it so:
        1v1Stat - Kills: (934 Dmg, 4 Kills) (23 Common)
        1v1Stat - Skeet: (1 Normal, 3 Injured) (5 Deadstops)
        1v1Stat - Acc. : (Total [72%], Per Pellet [25%]) (3 Headshots)
    */

    // report
    // 1
    if (!(iBrevityFlags & BREV_SI))
    {
        if (!(iBrevityFlags & BREV_DMG)) {
            if (!(iBrevityFlags & BREV_CI)) {
                Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Kills: (\x05%d \x01damage,\x05 %d \x01kills)  (\x05%d \x01common)\n", iDidDamageAll[iClientPlaying], iGotKills[iClientPlaying], iGotCommon[iClientPlaying]);
            } else {
                Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Kills: (\x05%d \x01damage,\x05 %d \x01kills)\n", iDidDamageAll[iClientPlaying], iGotKills[iClientPlaying]);
            }
        } else {
            if (!(iBrevityFlags & BREV_CI)) {
                Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Kills: (\x05%d \x01kills, \x05 %d \x01common)\n", iGotKills[iClientPlaying], iGotCommon[iClientPlaying]);
            } else {
                Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Kills: (\x05%d \x01kills)\n", iGotKills[iClientPlaying]);
            }
        }
        StrCat(printBuffer, sizeof(printBuffer), tmpBuffer);

        if (!toClient) {
            PrintToServer("\x01%s", printBuffer);
            PrintToChatAll("\x01%s", printBuffer);
        } else if (IsClientAndInGame(toClient)) {
            PrintToChat(toClient, "\x01%s", printBuffer);
        }
        printBuffer = "";
    }

    if (!(iBrevityFlags & BREV_SKEET))
    {
        Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Skeet: (\x05%d \x01normal,\x05 %d \x01hurt)   (\x05%d \x01deadstops)\n", iHuntSkeets[iClientPlaying], iHuntSkeetsInj[iClientPlaying], iDeadStops[iClientPlaying]);
        StrCat(printBuffer, sizeof(printBuffer), tmpBuffer);

        if (!toClient) {
            PrintToServer("\x01%s", printBuffer);
            PrintToChatAll("\x01%s", printBuffer);
        } else if (IsClientAndInGame(toClient)) {
            PrintToChat(toClient, "\x01%s", printBuffer);
        }
        printBuffer = "";
    }

    if (!(iBrevityFlags & BREV_ACC))
    {
        if (iShotsFired[iClientPlaying] || (iMeleesFired[iClientPlaying] && !(iBrevityFlags & BREV_MELEE))) {
            if (iShotsFired[iClientPlaying]) {
                Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Acc. : (all shots [\x04%3.0f%%\x01]", float(iShotsHit[iClientPlaying]) / float(iShotsFired[iClientPlaying]) * 100);
            } else {
                Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Acc. : (all shots [\x04%3.0f%%\x01]", 0.0);
            }
            if (iPelletsFired[iClientPlaying]) {
                StrCat(printBuffer, sizeof(printBuffer), tmpBuffer);
                Format(tmpBuffer, sizeof(tmpBuffer), ", buckshot [\x04%3.0f%%\x01]", float(iPelletsHit[iClientPlaying]) / float(iPelletsFired[iClientPlaying]) * 100);
            }
            if (iMeleesFired[iClientPlaying] && !(iBrevityFlags & BREV_MELEE)) {
                StrCat(printBuffer, sizeof(printBuffer), tmpBuffer);
                Format(tmpBuffer, sizeof(tmpBuffer), ", melee [\x04%3.0f%%\x01]", float(iMeleesHit[iClientPlaying]) / float(iMeleesFired[iClientPlaying]) * 100);
            }
            StrCat(printBuffer, sizeof(printBuffer), tmpBuffer);
            Format(tmpBuffer, sizeof(tmpBuffer), ")\n");
        } else {
            Format(tmpBuffer, sizeof(tmpBuffer), "1v1Stat - Acc. : (no shots fired)\n");
        }
        StrCat(printBuffer, sizeof(printBuffer), tmpBuffer);

        if (!toClient) {
            PrintToServer("\x01%s", printBuffer);
            PrintToChatAll("\x01%s", printBuffer);
        } else if (IsClientAndInGame(toClient)) {
            PrintToChat(toClient, "\x01%s", printBuffer);
        }
        printBuffer = "";
    }
}

bool:IsRupEnable()
{
    return GetFeatureStatus(FeatureType_Native, "L4DReady_IsReadyMode") == FeatureStatus_Available && L4DReady_IsReadyMode();
}
/*
 *      general functions
 *      =================
 */

// resolve hits, for the final shotgun blasts before wipe/saferoom
public ResolveOpenShots() {

    if (iClientPlaying <= 0) { return; }

    // if there's any shotgun blast not 'closed', close it
    if (iPreviousShotType[iClientPlaying])
    {
        if (bCurrentShotHit[iClientPlaying]) {
            if (iPreviousShotType[iClientPlaying] == WP_MELEE) {
                // melee hit
                iMeleesHit[iClientPlaying]++;

            } else {
                // shotgun hit
                iShotsHit[iClientPlaying]++;

                // base hit pellets on amount of damage done
                // based on weaponId differences aswell since shotties do different amounts of damage
                // what to do about damage dropoff? ignore?
                if (iCurrentShotDmg[iClientPlaying]) {
                    new iTotalPellets, iPelletDamage;
                    switch (iPreviousShotType[iClientPlaying]) {
                        case WP_PUMPSHOTGUN:    { iTotalPellets = 10; iPelletDamage = 25; }
                        case WP_AUTOSHOTGUN:    { iTotalPellets = 12; iPelletDamage = 25; }
                    }
                    if (iTotalPellets) {
                        new addPellets = RoundFloat(float(iCurrentShotDmg[iClientPlaying] / iPelletDamage ));
                        iPelletsHit[iClientPlaying] += (addPellets <= iTotalPellets) ? addPellets : iTotalPellets;
                    }
                    // test
                    //PrintToChatAll("RESOLVE: %d hit, damage %d, dmg/pellet %d", RoundFloat(float(iCurrentShotDmg[iClientPlaying] / iPelletDamage )), iCurrentShotDmg[iClientPlaying], iPelletDamage);
                }
            }
        }
        iPreviousShotType[iClientPlaying] = 0;
    }
}


// get type of weapon fired, diff between shotgun, melee and bullets
stock GetWeaponType(weaponId) {
    // 1. shotgun
    if (        weaponId == WP_PUMPSHOTGUN      ||
                weaponId == WP_AUTOSHOTGUN
    ) {
                return WPTYPE_SHELLS;
    }

    // 2. melee
    if (weaponId == WP_MELEE)
    {
                return WPTYPE_MELEE;
    }

    // 3. rifles / snipers / pistols (per shot accuracy)
    if (        weaponId == WP_PISTOL           ||
                weaponId == WP_SMG              ||
                weaponId == WP_HUNTING_RIFLE    ||
                weaponId == WP_RIFLE
    ) {
                return WPTYPE_BULLETS;
    }
    return WPTYPE_NONE;
}


// get 1v1 survivor player
stock GetCurrentSurvivor() {
    // assuming only 1, just get the first one
    new i, maxplayers = MaxClients;
    for (i = 1; i <= maxplayers; i++)
    {
        if (IsSurvivor(i)) { return i; }
    }
    return -1;
}

// clear all stats for client
stock ClearClientSkeetStats(client) {
    iGotKills[client] = 0;
    iGotCommon[client] = 0;
    iDidDamage[client] = 0;
    iDidDamageAll[client] = 0;
    iDidDamageWitch[client] = 0;
    iDidDamageTank[client] = 0;

    iShotsFired[client] = 0;
    iPelletsFired[client] = 0;
    iShotsHit[client] = 0;
    iPelletsHit[client] = 0;
    iMeleesFired[client] = 0;
    iMeleesHit[client] = 0;
    iDeadStops[client] = 0;
    iHuntSkeets[client] = 0;
    iHuntSkeetsInj[client] = 0;
    iHuntHeadShots[client] = 0;

    fPreviousShot[client] = 0.0;
    iPreviousShotType[client] = 0;
    bCurrentShotHit[client] = 0;
    iCurrentShotDmg[client] = 0;

    bIsPouncing[client] = false;
    bIsHurt[client] = false;
    iDmgDuringPounce[client] = 0;
}
