package bh.platform
{
   import flash.utils.Dictionary;
   import flash.utils.getTimer;

   public final class BotLevels
   {
      public static const ASCENDED:uint = 18;
      public static const CHOSEN:uint = 8;

      private static const SHORT_KEY:String = "BotDifficulty_Ascended";
      private static const FULL_KEY:String = "BotDifficultyFull_Ascended";
      private static const TRAINING_KEY:String = "UI_TrainingSettings_Trainer_Ascended";

      private static var ascended:Dictionary = new Dictionary(true);

      private static var partyListDone:Boolean = false;

      private static var reactOn:Boolean = false;

      private static var thinkMs:uint = 48;

      private static var comboThinkMs:uint = 0;

      private static var dodgeLead:uint = 0;

      private static var dodgeAway:Boolean = false;

      private static var pressed:Dictionary = new Dictionary(true);

      private static var threat:class_39 = new class_39();

      private static var dodges:uint = 0;

      private static var patienceMs:uint = 0;

      private static var waited:uint = 0;

      private static var engageFactor:Number = -1;

      private static var engaged:uint = 0;

      private static var leadMs:uint = 0;

      private static var leads:uint = 0;

      private static var readMs:uint = 300;

      private static var reads:uint = 0;

      private static var thinkingIsAscended:Boolean = false;

      private static function thinkingAscended() : Boolean
      {
         return thinkingIsAscended;
      }

      private static var readSeen:Array = [0,0,0,0,0,0];

      private static var ascendedLegends:Dictionary = new Dictionary(true);

      private static var neutralLog:Boolean = false;

      private static var neutralStates:Dictionary = new Dictionary(true);

      private static var diMode:uint = 0;

      private static var recoveryDrifts:uint = 0;

      private static var holdBelow:Number = -1;

      private static var jumpHolds:uint = 0;

      private static var ledgeAwayRange:Number = -1;

      private static var ledgePicks:uint = 0;

      private static var ledgesAway:uint = 0;

      private static var holding:Dictionary = new Dictionary(true);

      private static var recoverDodge:Boolean = true;

      private static var recoveryDodges:uint = 0;

      private static var punishMode:uint = 0;

      private static var punishThinks:uint = 0;

      private static var punishing:Dictionary = new Dictionary(true);

      private static var punished:uint = 0;

      private static var unpunished:uint = 0;

      public function BotLevels()
      {
      }

      public static function level(brain:Object) : uint
      {
         return brain == null ? 0 : (ascended[brain] ? ASCENDED : uint(brain.var_9930));
      }

      public static function setUp(brain:Object) : void
      {
         if(uint(brain.var_9930) == ASCENDED)
         {
            brain.var_9930 = CHOSEN;
            if(!ascended[brain])
            {
               Platform.log("bot level: Ascended (set up as Chosen, then tuned)");
            }
            ascended[brain] = true;
            if(brain.var_7193 != null)
            {
               ascendedLegends[brain.var_7193] = true;
            }
            ensureLists();
         }
         else if(ascended[brain])
         {
            delete ascended[brain];
            if(brain.var_7193 != null)
            {
               delete ascendedLegends[brain.var_7193];
            }
         }
      }

      public static function holdJumps(state:Object, now:uint, rising:Boolean, jumpsLeft:int) : Boolean
      {
         if(rising || holdBelow < 0 || jumpsLeft <= 0 || !ascended[state.var_790])
         {
            return rising;
         }
         var target:Object = state.var_12777;
         var me:class_123 = state.var_7193 as class_123;
         if(target == null || me == null || Number(me.method_4344()) >= Number(target.startY) + holdBelow)
         {
            return false;
         }
         jumpHolds++;
         return true;
      }

      public static function recoverLedge(brain:Object, edges:Boolean) : void
      {
         if(ledgeAwayRange < 0 || !ascended[brain] || brain.var_3163 == null)
         {
            return;
         }
         var me:class_123 = brain.var_7193 as class_123;
         var foe:class_123 = brain.method_4941() as class_123;
         if(me == null || foe == null)
         {
            return;
         }
         var x:Number = me.var_10228.method_113(me.var_6005);
         var y:Number = me.var_10228.method_113(me.var_4126);
         var fx:Number = foe.var_10228.method_113(foe.var_6005);
         var fy:Number = foe.var_10228.method_113(foe.var_4126);
         var nodes:Object = brain.var_11702.var_3623;
         var best:Object = null;
         var bestScore:Number = Number.MAX_VALUE;
         for(var i:int = 0; i < int(nodes.length); i++)
         {
            var n:Object = nodes[i];
            if(n == null || uint(n.var_3782) != 4 && (!edges || uint(n.var_3782) != 2))
            {
               continue;
            }
            var nx:Number = Number(n.var_10952);
            var ny:Number = Number(n.var_4205);
            var score:Number = Math.abs(nx - x) + (ny > y ? ny - y : 1.5 * (y - ny));
            var near:Number = ledgeAwayRange - Math.sqrt((nx - fx) * (nx - fx) + (ny - fy) * (ny - fy));
            if(near > 0)
            {
               score += 2 * near;
            }
            if(score < bestScore)
            {
               best = n;
               bestScore = score;
            }
         }
         ledgePicks++;
         if(best == null || best == brain.var_3163)
         {
            return;
         }
         ledgesAway++;
         brain.var_3163 = best;
         brain.var_11702.method_6522(brain.var_5863,brain.var_12814,brain.var_3163,me.var_3540);
      }

      private static var lastTune:int = -100000;

      private static function resetTallies() : void
      {
         var t:int = getTimer();
         if(t - lastTune > 2000)
         {
            dodges = 0;
            waited = 0;
            engaged = 0;
            leads = 0;
            reads = 0;
            recoveryDrifts = 0;
            jumpHolds = 0;
            ledgePicks = 0;
            ledgesAway = 0;
            recoveryDodges = 0;
            punishThinks = 0;
            punished = 0;
            unpunished = 0;
            readSeen = [0,0,0,0,0,0];
         }
         lastTune = t;
      }

      public static function tune(brain:Object) : void
      {
         resetTallies();
         if(!ascended[brain])
         {
            if(uint(brain.var_9930) == CHOSEN)
            {
               hitLog = setting("botHitLog",0) != 0;
               neutralLog = setting("botNeutralLog",0) != 0;
               logDraws(brain,"Chosen");
            }
            return;
         }
         brain.var_10754 = setting("ascendedAccurate",1);
         brain.var_4997 = uint(setting("ascendedWindow",128));
         brain.var_1218 = setting("ascendedAct",0.85);
         brain.var_7126 = uint(setting("ascendedReplan",75));
         brain.var_13033 = uint(brain.var_13033) | uint(setting("ascendedFlags",0x2000));
         fix(brain,"var_8153","ascendedIdle");
         fix(brain,"var_14659","ascendedRecover");
         fix(brain,"var_6590","ascendedHold");
         var chase:Number = setting("ascendedChase",-1);
         if(chase >= 0)
         {
            brain.var_788 = chase;
         }
         reactOn = setting("ascendedReact",0) != 0;
         hitLog = setting("botHitLog",0) != 0;
         thinkMs = uint(setting("ascendedThink",48));
         comboThinkMs = uint(setting("ascendedComboThink",0));
         dodgeLead = uint(setting("ascendedDodge",96));
         dodgeAway = setting("ascendedDodgeAway",1) != 0;
         recoverDodge = setting("ascendedRecoverDodge",1) != 0;
         punishMode = uint(setting("ascendedPunish",2));
         diMode = uint(setting("ascendedDI",0));
         holdBelow = setting("ascendedHoldJumps",-1);
         ledgeAwayRange = setting("ascendedLedgeAway",-1);
         patienceMs = uint(setting("ascendedPatience",0));
         engageFactor = setting("ascendedEngage",-1);
         leadMs = uint(setting("ascendedLead",0));
         readMs = uint(setting("ascendedReadInputs",300));
         neutralLog = setting("botNeutralLog",0) != 0;
         logDraws(brain,"Ascended");
      }

      public static function engage(state:Object, target:Object) : Boolean
      {
         if(engageFactor < 0 || target == null || uint(state.var_1387) != 1)
         {
            return false;
         }
         var brain:Object = state.var_790;
         if(!ascended[brain] || !brain.var_14559)
         {
            return false;
         }
         var me:class_123 = state.var_7193 as class_123;
         var foe:class_123 = target as class_123;
         if(me == null || foe == null || foe.var_3540 == me.var_3540)
         {
            return false;
         }
         var x:Number = me.method_338();
         var y:Number = me.method_4344();
         var fx:Number = x - foe.method_338();
         var fy:Number = y - foe.method_4344();
         var sx:Number = x - Number(brain.var_9596.x);
         var sy:Number = y - Number(brain.var_9596.y);
         if(engageFactor * (fx * fx + fy * fy) >= sx * sx + sy * sy)
         {
            return false;
         }
         engaged++;
         if(engaged <= 5 || engaged % 200 == 0)
         {
            Platform.log("ascended engage " + engaged + ": opponent at " + int(Math.sqrt(fx * fx + fy * fy)) + ", spot at " + int(Math.sqrt(sx * sx + sy * sy)));
         }
         return true;
      }

      public static function lead(flags:uint, target:class_123) : void
      {
         if(readMs != 0)
         {
            readSeen[3]++;
            if(thinkingAscended())
            {
               readSeen[4]++;
            }
            if(target != null && ascendedLegends[target])
            {
               readSeen[5]++;
            }
         }
         if(leadMs == 0 && readMs == 0 || !thinkingAscended() || target == null || ascendedLegends[target])
         {
            return;
         }
         readSeen[0]++;
         if(target.var_2000.var_9222 != null || target.method_503() && uint(target.var_9413 + target.var_8895) > uint(target.owner.var_1171))
         {
            return;
         }
         readSeen[1]++;
         var vx:Number = target.var_10228.method_113(target.var_15078);
         if(vx * vx < 1)
         {
            return;
         }
         readSeen[2]++;
         var ms:uint = leadMs;
         if(readMs != 0)
         {
            var keys:uint = target.var_10012 == null ? 0 : uint(target.var_10012.var_13063) & (4 | 8);
            if(keys == 0 || keys == 4 && vx > 0 || keys == 8 && vx < 0)
            {
               return;
            }
            ms = readMs;
            reads++;
         }
         var xs:Vector.<Number> = class_637.var_7640;
         var n:int = int(xs.length);
         var k:int = Math.min(n,Math.ceil(ms / 16));
         if(k <= 0)
         {
            return;
         }
         var step:Number = vx * class_51.var_12355;
         var base:Number = xs[k - 1];
         var held:Number = step * k;
         for(var i:int = 0; i < n; i++)
         {
            xs[i] = i < k ? step * (i + 1) : held + (xs[i] - base);
         }
         leads++;
         if(leads <= 3 || leads % 2000 == 0)
         {
            Platform.log("ascended lead " + leads + (readMs != 0 ? " (input read)" : "") + ": speed " + vx.toFixed(2) + ", " + k + " steps held, x at " + k + " " + int(base) + " -> " + int(held));
         }
      }

      public static function react(brain:Object, own:Object, threat:Object) : Boolean
      {
         return reactOn && ascended[brain] && int(own.var_10614) >= int(threat.var_10614);
      }

      public static function patience(brain:Object, foe:Object, own:Object, now:uint) : void
      {
         if(patienceMs == 0 || !ascended[brain] || int(own.var_10614) == 2147483647)
         {
            return;
         }
         if(int(own.var_10614) - int(now) <= int(patienceMs))
         {
            return;
         }
         var f:class_123 = foe as class_123;
         if(f == null || f.var_2000.var_9222 != null || f.method_2791(now))
         {
            return;
         }
         if(f.method_503() && uint(f.var_9413 + f.var_8895) > now)
         {
            return;
         }
         own.var_10614 = 2147483647;
         waited++;
         if(waited <= 5 || waited % 200 == 0)
         {
            Platform.log("ascended patience " + waited + ": attack dropped");
         }
      }

      public static function thought(brain:Object, now:uint) : void
      {
         if(ascended[brain])
         {
            brain.var_5696 = now + thinkMs;
            if(punishMode == 1 && punishing[brain] && punishing[brain].foe.var_2000.var_9222 != null)
            {
               brain.var_5696 = now + 16;
               return;
            }
            if(comboThinkMs != 0)
            {
               var foe:class_123 = brain.method_4941() as class_123;
               if(foe != null && foe.method_503() && uint(foe.var_9413 + foe.var_8895) > now)
               {
                  brain.var_5696 = now + comboThinkMs;
               }
            }
         }
      }

      public static function dodge(brain:Object, now:uint) : Boolean
      {
         thinkingIsAscended = ascended[brain] == true;
         if(hitLog)
         {
            countHits(brain,now);
         }
         if(neutralLog)
         {
            countNeutral(brain,now);
         }
         if(diMode != 0 && ascended[brain] && holdDI(brain,now))
         {
            return true;
         }
         if(dodgeLead == 0 || !ascended[brain])
         {
            return false;
         }
         if(punishing[brain])
         {
            punish(brain,now);
         }
         if(pressed[brain])
         {
            delete pressed[brain];
            brain.var_12188.method_75();
            return false;
         }
         var me:class_123 = brain.var_7193 as class_123;
         if(me == null || me.var_661 != 0 && me.var_661 != 5 || me.method_2791(now))
         {
            return false;
         }
         if(me.method_503() && uint(me.var_9413 + me.var_8895) > now)
         {
            return false;
         }
         var foe:class_123 = brain.method_4941() as class_123;
         if(foe == null || foe.var_2000.var_9222 == null || !foe.var_2000.var_9222.var_9412)
         {
            return false;
         }
         var step:uint = uint(brain.owner.var_1171);
         step = uint(step - step % 16 + 16);
         class_40.var_10912.method_5554(now,me);
         class_40.var_10912.method_5554(now,foe);
         class_40.var_10912.method_498(threat,now,step,foe,me,uint(brain.var_13033),false);
         var lands:int = threat.var_10614;
         if(lands == 2147483647 || lands < int(now) || lands > int(now + dodgeLead))
         {
            return false;
         }
         var recovering:Boolean = recoverDodge && brain.var_13063 is class_185;
         if(recovering)
         {
            recoveryDodges++;
         }
         brain.method_7096(dodgeAway || recovering ? brain.method_8920(threat,recovering) : 0,true);
         pressed[brain] = true;
         punishing[brain] = {"foe":foe,"hit":uint(foe.var_8895),"until":now + 1000};
         dodges++;
         if(dodges <= 5 || dodges % 50 == 0)
         {
            Platform.log("ascended dodge " + dodges + ": hit predicted in " + (lands - int(now)) + " ms");
         }
         return true;
      }

      private static function punish(brain:Object, now:uint) : void
      {
         var p:Object = punishing[brain];
         var foe:class_123 = p.foe as class_123;
         var me:class_123 = brain.var_7193 as class_123;
         if(punishMode == 2 && !p.thought && me != null && foe.var_2000.var_9222 != null && !me.method_5215(now))
         {
            brain.var_5696 = now;
            p.thought = true;
            punishThinks++;
         }
         var hit:Boolean = uint(foe.var_8895) != uint(p.hit) && uint(foe.var_8895) != 0;
         if(!hit && now <= uint(p.until))
         {
            return;
         }
         delete punishing[brain];
         if(hit)
         {
            punished++;
         }
         else
         {
            unpunished++;
         }
         if(hitLog && (punished + unpunished) % 5 == 0)
         {
            ErrorLog.write("platform: ascended punish: " + punished + " of " + (punished + unpunished) + " dodges punished within 1 s" +
               (punishMode == 2 ? "; punish thinks " + punishThinks : ""));
         }
      }

      private static function holdDI(brain:Object, now:uint) : Boolean
      {
         var me:class_123 = brain.var_7193 as class_123;
         var stunned:Boolean = me != null && me.method_503() && uint(me.var_9413 + me.var_8895) > now;
         if(!stunned)
         {
            if(holding[brain])
            {
               delete holding[brain];
               brain.var_12188.method_75();
            }
            return false;
         }
         var away:Boolean;
         if(diMode == 3)
         {
            if(!(brain.var_13063 is class_185) || brain.var_3163 == null)
            {
               if(holding[brain])
               {
                  delete holding[brain];
                  brain.var_12188.method_75();
               }
               return false;
            }
            away = Number(brain.var_3163.var_10952) > me.var_10228.method_113(me.var_10836);
            recoveryDrifts++;
         }
         else
         {
            var foe:class_123 = brain.method_4941() as class_123;
            if(foe == null)
            {
               return false;
            }
            away = me.var_10228.method_113(me.var_10836) >= foe.var_10228.method_113(foe.var_10836);
            if(diMode == 2)
            {
               away = !away;
            }
         }
         brain.var_12188.method_75();
         if(away)
         {
            brain.var_12188.Right();
         }
         else
         {
            brain.var_12188.Left();
         }
         holding[brain] = true;
         return true;
      }

      private static const KO_AFTER_HIT:uint = 1200;

      private static var hitLog:Boolean = false;

      private static var hitStates:Dictionary = new Dictionary(true);

      private static function countHits(brain:Object, now:uint) : void
      {
         var lv:uint = level(brain);
         if(lv != ASCENDED && lv != CHOSEN)
         {
            return;
         }
         var me:class_123 = brain.var_7193 as class_123;
         if(me == null)
         {
            return;
         }
         var st:Object = hitStates[brain];
         if(st == null)
         {
            st = hitStates[brain] = {"hit":uint(me.var_8895),"stun":false,"move":false,"cool":false,"foe":false,"n":0,
               "combo":0,"inMove":0,"noDodge":0,"freeFoeMove":0,"free":0,"pending":false,"di":0,
               "ko":false,"born":now,"rec":false,"kos":0,"gimped":0,"hitKos":0};
         }
         var ko:Boolean = uint(me.var_661) == 3;
         if(ko && !st.ko && now > uint(st.born) + 5000)
         {
            st.kos++;
            if(st.rec)
            {
               st.gimped++;
            }
            if(now < uint(me.var_8895) + KO_AFTER_HIT)
            {
               st.hitKos++;
            }
            ErrorLog.write("platform: bot stocks (" + (lv == ASCENDED ? "Ascended" : "Chosen") + " " + me.var_11355 + "): " +
               st.kos + " lost, " + st.gimped + " while recovering, " + st.hitKos + " right after a hit" +
               (lv == ASCENDED ? "; recovery dodges so far " + recoveryDodges + ", drift steps " + recoveryDrifts +
               ", jump holds " + jumpHolds + ", ledges away " + ledgesAway + " of " + ledgePicks : ""));
         }
         st.ko = ko;
         if(!ko)
         {
            st.rec = brain.var_13063 is class_185;
         }
         if(st.pending && me.var_2000.var_11600)
         {
            st.di++;
         }
         st.pending = false;
         if(uint(me.var_8895) != uint(st.hit) && uint(me.var_8895) != 0)
         {
            st.n++;
            st.pending = true;
            if(st.stun)
            {
               st.combo++;
            }
            else if(st.move)
            {
               st.inMove++;
            }
            else if(st.cool)
            {
               st.noDodge++;
            }
            else if(st.foe)
            {
               st.freeFoeMove++;
            }
            else
            {
               st.free++;
            }
            if(st.n % 25 == 0)
            {
               ErrorLog.write("platform: bot hits (" + (lv == ASCENDED ? "Ascended" : "Chosen") + " " + me.var_11355 + "): " + st.n +
                  " taken; in hitstun " + st.combo + ", in own move " + st.inMove + ", dodge unavailable " + st.noDodge +
                  ", free while the opponent attacked " + st.freeFoeMove + ", free otherwise " + st.free +
                  "; DI applied to " + st.di + (lv == ASCENDED ? "; Ascended dodges so far " + dodges : "") +
                  (lv == ASCENDED && readMs != 0 ? "; inputs read so far " + reads + " (of " + readSeen[0] + " plans, " +
                  readSeen[1] + " with the opponent free, " + readSeen[2] + " moving; path calls " + readSeen[3] + ", " +
                  readSeen[4] + " Ascended's, " + readSeen[5] + " for its own legend)" : ""));
            }
         }
         st.hit = uint(me.var_8895);
         st.stun = me.method_503() && uint(me.var_9413 + me.var_8895) > now;
         st.move = me.var_2000.var_9222 != null;
         st.cool = me.method_2791(now);
         var foe:class_123 = brain.method_4941() as class_123;
         st.foe = foe != null && foe.var_2000.var_9222 != null;
      }

      private static function countNeutral(brain:Object, now:uint) : void
      {
         var lv:uint = level(brain);
         if(lv != ASCENDED && lv != CHOSEN)
         {
            return;
         }
         var me:class_123 = brain.var_7193 as class_123;
         var foe:class_123 = brain.method_4941() as class_123;
         if(me == null || foe == null)
         {
            return;
         }
         var st:Object = neutralStates[brain];
         if(st == null)
         {
            st = neutralStates[brain] = {"inMove":true,"foeHit":uint(foe.var_8895),"was":0,"t":now,
               "freeMs":0,"movingMs":0,"starts":0,"startsMoving":0,"hits":0,"hitsMoving":0,"logged":0};
         }
         var gap:uint = now > uint(st.t) && now - uint(st.t) < 100 ? now - uint(st.t) : 0;
         st.t = now;
         var inMove:Boolean = me.var_2000.var_9222 != null;
         if(uint(foe.var_8895) != uint(st.foeHit) && uint(foe.var_8895) != 0)
         {
            if(st.was == 1)
            {
               st.hits++;
            }
            else if(st.was == 2)
            {
               st.hitsMoving++;
            }
         }
         st.foeHit = uint(foe.var_8895);
         if(inMove && !st.inMove)
         {
            if(st.was == 1)
            {
               st.starts++;
            }
            else if(st.was == 2)
            {
               st.startsMoving++;
            }
         }
         st.inMove = inMove;
         var free:Boolean = foe.var_2000.var_9222 == null && !(foe.method_503() && uint(foe.var_9413 + foe.var_8895) > now) && (foe.var_661 == 0 || foe.var_661 == 5);
         var vx:Number = free ? foe.var_10228.method_113(foe.var_15078) : 0;
         st.was = !free ? 0 : (vx * vx >= 1 ? 2 : 1);
         if(st.was == 1)
         {
            st.freeMs += gap;
         }
         else if(st.was == 2)
         {
            st.movingMs += gap;
         }
         var total:uint = uint(st.freeMs) + uint(st.movingMs);
         if(total >= uint(st.logged) + 10000)
         {
            st.logged = total;
            ErrorLog.write("platform: bot neutral (" + (lv == ASCENDED ? "Ascended" : "Chosen") + " " + me.var_11355 + ", lead " + leadMs + "): foe standing " +
               (uint(st.freeMs) / 1000).toFixed(1) + " s, " + st.starts + " moves started, " + st.hits + " hits; foe moving " +
               (uint(st.movingMs) / 1000).toFixed(1) + " s, " + st.startsMoving + " moves started, " + st.hitsMoving + " hits");
         }
      }

      private static function logDraws(brain:Object, name:String) : void
      {
         var text:String = "bot draws (" + name + "): idle " + Number(brain.var_8153).toFixed(2) + ", recover " +
            Number(brain.var_14659).toFixed(2) + ", hold " + Number(brain.var_6590).toFixed(2) + ", platform " +
            Number(brain.var_1208).toFixed(2) + ", chase " + Number(brain.var_788).toFixed(2);
         if(hitLog)
         {
            ErrorLog.write("platform: " + text);
         }
         else
         {
            Platform.log(text);
         }
      }

      private static function fix(brain:Object, field:String, name:String) : void
      {
         var v:Number = setting(name,NaN);
         if(!isNaN(v))
         {
            brain[field] = v;
         }
      }

      public static function shortName(level:uint) : String
      {
         ensureLists();
         if(level != ASCENDED)
         {
            return null;
         }
         registerNames();
         return SHORT_KEY;
      }

      public static function fullName(level:uint) : String
      {
         ensureLists();
         if(level != ASCENDED)
         {
            return null;
         }
         registerNames();
         return FULL_KEY;
      }

      public static function trainingLists() : void
      {
         try
         {
            var levels:Array = class_551.var_4122;
            if(levels != null && levels.indexOf(ASCENDED) < 0)
            {
               levels.push(ASCENDED);
            }
            Object(class_551.var_4512).h[ASCENDED] = TRAINING_KEY;
            registerNames();
         }
         catch(e:Error)
         {
            Platform.log("bot levels (training): " + e.message);
         }
      }

      private static function ensureLists() : void
      {
         if(partyListDone)
         {
            return;
         }
         partyListDone = true;
         try
         {
            var party:Object = class_493.var_12832;
            if(party != null && party.indexOf(ASCENDED) < 0)
            {
               party.push(ASCENDED);
            }
         }
         catch(e:Error)
         {
            Platform.log("bot levels (party): " + e.message);
         }
      }

      private static function registerNames() : void
      {
         try
         {
            var table:Object = class_256.var_5943.var_15061;
            table.method_65(SHORT_KEY,"Ascended");
            table.method_65(FULL_KEY,"Ascended");
            table.method_65(TRAINING_KEY,"Ascended");
         }
         catch(e:Error)
         {
         }
      }

      private static function setting(name:String, otherwise:Number) : Number
      {
         var v:* = ModSettings.value(name);
         return v == null || isNaN(Number(v)) ? otherwise : Number(v);
      }
   }
}
