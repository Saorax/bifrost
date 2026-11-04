package bh.platform
{
   public final class FieldHelp
   {
      private static const PER_PART:Object = {"VariableImpulse":1,"FixedImpulse":1,"FireImpulseX":1,"FireImpulseY":1,
         "FireImpulseMaxX":1,"AoERadiusX":1,"AoERadiusY":1,"CenterOffsetX":1,"CenterOffsetY":1,"BaseDamage":1,
         "ImpulseOffsetX":1,"ImpulseOffsetY":1,"ImpulseOffsetMaxX":1,"CastGfxRotation":1,"FixedStunTime":1,"AccelMult":1};
      private static const SHAPES:Object = {"AoERadiusX":1,"AoERadiusY":1,"CenterOffsetX":1,"CenterOffsetY":1,
         "BaseDamage":1,"VariableImpulse":1,"FixedImpulse":1,"ImpulseOffsetX":1,"ImpulseOffsetY":1};

      private static const ABOUT:Object = {
         "DevNotes":"The developers' notes; not used by the game.",
         "MissionTags":"Tags missions count this move by.",
         "Priority":"0-100: which move wins when two hit on the same frame (higher wins).",
         "ItemHitSoundEvent":"The sound played when it hits a thrown item.",
         "ParentItem":"The weapon (or item) this move belongs to.",
         "OriginPower":"The move this one is a variant of.",
         "IsAirPower":"TRUE for an aerial move.",
         "IsSignature":"TRUE for a signature.",
         "IsAntiair":"TRUE when the move counts as an anti-air.",
         "SigModeSwapsMove":"In signature-swap modes, this move is swapped.",
         "ImpulseMaxOnDCOnly":"The FireImpulseMaxX cap only applies on a dash cancel.",
         "SpeedLimitY":"Top up/down speed while using it.",
         "SpeedLimitAttack":"Top speed while the move is active.",
         "SpeedLimitBackward":"Top speed moving backwards.",
         "SpeedLimitAttackBackward":"Top backwards speed while the move is active.",
         "EndOnHit":"The move ends when it hits.",
         "WallCancel":"Touching a wall ends the move.",
         "AllowRecoverMove":"The legend can move during the recovery.",
         "AllowJumpDuringRecover":"The legend can jump during the recovery.",
         "AllowLeaveGround":"The move may leave the ground (walk off edges).",
         "AllowHitOnZeroDamage":"A hit with 0 damage still counts as a hit.",
         "AccelMult":"Acceleration multiplier while using it (per part).",
         "BackwardAccelMult":"Acceleration multiplier when moving backwards.",
         "TurnOffDampening":"No speed dampening during the move.",
         "KeepGroundFriction":"Ground friction stays on.",
         "IgnoreGroundRestrict":"Ignores the ground's limits on movement.",
         "DoNotBounceOffNoSlideCeiling":"Doesn't bounce off ceilings you can't slide along.",
         "NoSlideCeilingBuffer":"Distance kept from such ceilings.",
         "Hurtbox":"The hurtbox the legend has during the move (a hurtbox name).",
         "IgnoreForcedFallTime":"Frames during which a forced fall is ignored.",
         "ShowCloudTime":"Frames the dust cloud shows.",
         "IgnoreCDOverride":"Ignores cooldown overrides.",
         "ShakeTime":"Frames of screen shake on hit.",
         "DisableShake":"No screen shake.",
         "OnlyShakeOnce":"Screen shake once per move.",
         "ShakeAllCams":"Shakes every player's camera.",
         "LoseInvulnTime":"Frame at which the legend's spawn invulnerability is lost.",
         "PostHitDamageMultiplier":"Damage multiplier for hits after the first.",
         "PostHitImpulseMultiplier":"Knockback multiplier for hits after the first.",
         "ImpulseOffsetMaxX":"Cap of the knockback's sideways part (per part).",
         "ImpulseToPoint":"Knockback pulls toward a point instead of a direction.",
         "ToPointChangeX":"For ImpulseToPoint: the point's sideways offset.",
         "ToPointChangeY":"For ImpulseToPoint: the point's up/down offset.",
         "ToPointChangeDmg":"For ImpulseToPoint: damage at which it changes.",
         "LockTo45Degrees":"Knockback snaps to 45-degree directions.",
         "DownwardForceMult":"Multiplier for downward knockback.",
         "MirrorImpulseOffset":"The knockback direction is mirrored on the far side of the hitbox.",
         "MirrorOffsetCenter":"Where that mirroring happens.",
         "IgnoreStrength":"The legend's Strength doesn't change the damage.",
         "AcceptInput":"The move reads input while active.",
         "HeldDirOffsets":"Hitbox offsets for a held direction (one per direction).",
         "ImpulseOnHeavy":"Extra growing knockback added on a heavy hit (added to VariableImpulse).",
         "ItemSpeedDamage":"Thrown items: damage added per unit of the item's speed (speed x this).",
         "ItemSpeedImpulse":"Thrown items: knockback added from the item's speed (speed x this x 0.5).",
         "ItemHitElasticity":"Thrown items: how much the item bounces off what it hits.",
         "AirTimeMultOnly":"Only the air time multiplier applies.",
         "InheritAlreadyHit":"Targets the previous move hit can't be hit again by this one.",
         "InterruptThreshold":"Damage taken during the move before it's interrupted.",
         "CanDamageEveryone":"Hits teammates too.",
         "CanAssist":"Counts for assists.",
         "ConsumesWeapon":"Uses up the weapon (throws).",
         "HoldHitEnts":"Grabs the targets it hits and carries them.",
         "HoldOffsetX":"Where carried targets are held, sideways.",
         "HoldOffsetY":"Where carried targets are held, up/down.",
         "UpdateHeldEnts":"Carried targets move with the move each frame.",
         "DestroysItemOnHit":"Destroys the item it hits.",
         "GrabInterpolateTime":"Frames to move a grabbed target into place.",
         "GrabAnim":"The grabbed target's animation.",
         "GrabAnimSpeed":"Speed of that animation.",
         "GrabForceUpdate":"Updates the grabbed target every frame.",
         "Uninterruptable":"Can't be interrupted by hits.",
         "CanChangeDirection":"The legend can turn around during it.",
         "OriginOverrideIfInMode":"Another origin move in some game modes.",
         "ComboOverrideIfDir":"Next move by held direction (\"UP:Move,DOWN:Move\").",
         "ComboOverrideIfInterrupt":"The move that follows when this one is interrupted.",
         "IgnoreButtonOnHit":"After a hit, the button doesn't change the follow-up.",
         "IgnoreButtonOnMiss":"After a miss, the button doesn't change the follow-up.",
         "ComboUseSameTargetPos":"The follow-up aims where this one did.",
         "UseCollisionAsTargetPos":"Aims at the collision point.",
         "ComboUseTargetAsSource":"The follow-up starts from the target.",
         "ComboUseSameSourcePos":"The follow-up starts from the same place.",
         "BGPowerOnFire":"A background move started at the active part.",
         "BGCastIdx":"The part at which it starts.",
         "AllowBGInterrupt":"The background move can be interrupted.",
         "PopulateActivePowerHits":"Hits count for the active move.",
         "PopulateBGHits":"Hits count for the background move.",
         "ExhaustedVersion":"The move used instead when exhausted (out of air jumps).",
         "GCVersion":"The move used instead after a gravity cancel.",
         "MomentumVersion":"The move used instead with momentum.",
         "TeamTauntPower":"The team taunt's move.",
         "AnimLayer":"The animation's layer.",
         "FXLayer":"The effects' layer.",
         "IsThrow":"A weapon throw.",
         "CannotAttackAroundCorners":"Can't hit through corners.",
         "ForceHitThroughSoftPlat":"Hits through soft platforms.",
         "ForceFaceRight":"Always faces right.",
         "CollisionPowerOffSetX":"Collision offset, sideways.",
         "CollisionPowerOffSetY":"Collision offset, up/down.",
         "DoNotSendSync":"Not synced online on its own.",
         "ForcePowerFacing":"Forces the facing direction.",
         "AnimSourceMidLinePos":"Where the animation's middle line is.",
         "HitReactAnim":"The target's reaction animation."};

      public static function about(col:String, known:String = null) : String
      {
         var what:String = known != null && known != "" ? known : ABOUT[col] != null ? ABOUT[col] : guess(col);
         var how:String = format(col);
         return what + (how != "" ? " " + how : "");
      }

      public static function format(col:String) : String
      {
         if(col == "CastTime")
         {
            return "Format: parts \",\" (one per hit); a part is \"W:A\": W wind-up frames, then A active frames. " +
               "\"W:A@K\" jumps the animation to keyframe K, \"W:A@K-E\" also to E at the end; \"W@K\": no active frames. " +
               "Example \"10:5@5-6,3:2\".";
         }
         if(col == "RecoverTime" || col == "FixedRecoverTime")
         {
            return "Format: frames; \"9@14\" also sets keyframe 14 for the recovery, \"9@end14\" keyframe 14 at its end.";
         }
         if(col == "CastAnim")
         {
            return "Format: an animation name; \"L:Name\", \"R:\", \"F:\" (or \"LR:\") add flags.";
         }
         if(PER_PART[col])
         {
            return "Format: one value, or one per CastTime part with \",\"; in a part, \"a~b\" goes from a to b over the " +
               "active frames, \"a|b\" alternates per frame, \"t30\" spreads 30 over them" +
               (SHAPES[col] ? ", \"a&b\" two hitboxes at once." : ".") +
               (col.indexOf("FireImpulse") == 0 ? " \"!\": no value." : "");
         }
         if(/^(Is|Allow|Can|Ignore|Keep|Turn|Do|Force|Mirror|Lock|Only|Shake|Update|Destroys|Consumes|Populate|End|Wall|Cancel|Uninterruptable|Disable)/.test(col))
         {
            return "TRUE or FALSE.";
         }
         if(/Time$/.test(col))
         {
            return "Frames (16 ms each).";
         }
         if(/^Combo|Version$|^OriginPower$|^OriginOverride|^BGPower/.test(col))
         {
            return "A move name (PowerName), or empty.";
         }
         return "";
      }

      private static function guess(col:String) : String
      {
         if(col.indexOf("Gfx") >= 0)
         {
            return "Visual effect setting (" + col + ").";
         }
         if(col.indexOf("Sound") >= 0)
         {
            return "A sound event name.";
         }
         return col + ".";
      }
   }
}
