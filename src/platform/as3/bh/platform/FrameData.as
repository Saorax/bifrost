package bh.platform
{
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.text.TextField;
   import flash.utils.Dictionary;

   public final class FrameData
   {
      public static const KEY:uint = 112;
      private static const TRAINING_MODE:uint = 32768;
      private static const STEP:uint = 16;

      private static var stage:Stage;
      private static var root:Sprite = null;
      private static var panel:Sprite = null;
      private static var field:TextField = null;
      private static var shown:String = "";
      private static var listening:Boolean = false;
      private static var legends:Array = [];
      private static var last:Object = null;
      private static var result:Object = null;
      public static var lastLine:String = "";
      public static var recent:Array = [];
      private static const RECENT:int = 4;

      public function FrameData()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.keyDown.add(onKey);
         Hooks.matchStarted.add(start);
         Hooks.matchEnded.add(function(state:uint):void
         {
            stop();
         });
      }

      public static function get on() : Boolean
      {
         return ModSettings.value("frameData") == true;
      }

      public static function set on(v:Boolean) : void
      {
         ModSettings.setValue("frameData",v);
         if(v)
         {
            start();
         }
         else
         {
            stop();
         }
      }

      private static function game() : Object
      {
         try
         {
            return ScreenManager.owner;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function inTraining(core:Object) : Boolean
      {
         return core != null && (uint(core.var_3595) & TRAINING_MODE) != 0;
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || !event.ctrlKey || event.shiftKey || event.altKey || uint(event.keyCode) != KEY)
         {
            return false;
         }
         if(!Platform.matchRunning || !inTraining(game()))
         {
            return false;
         }
         on = !on;
         return true;
      }

      private static function start() : void
      {
         if(!on || stage == null || listening)
         {
            return;
         }
         legends = [];
         last = result = null;
         recent = [];
         shown = "";
         Hooks.frameRendering.add(onFrame);
         listening = true;
      }

      private static function stop() : void
      {
         if(listening)
         {
            Hooks.frameRendering.remove(onFrame);
            listening = false;
         }
         if(root != null && root.parent != null)
         {
            root.parent.removeChild(root);
         }
         legends = [];
         last = result = null;
         recent = [];
      }

      private static function onFrame() : void
      {
         var core:Object = game();
         if(!Platform.matchRunning || !inTraining(core))
         {
            if(root != null && root.parent != null)
            {
               root.parent.removeChild(root);
            }
            return;
         }
         try
         {
            update(core);
         }
         catch(e:Error)
         {
            Platform.log("frame data: " + e.message);
            stop();
         }
      }

      private static function update(core:Object) : void
      {
         var now:uint = uint(core.var_13849);
         var frame:uint = now / STEP + 1;
         var players:Object = core.var_7050;
         var n:int = int(players.length);
         for(var i:int = 0; i < n; i++)
         {
            var p:Object = players[i];
            var s:Object = legends[i];
            if(s == null || s.player != p)
            {
               s = legends[i] = {"player":p,"seq":null,"hit":uint(p.var_8895)};
            }
            trackMoves(s,i,p,frame);
            var hit:uint = uint(p.var_8895);
            if(hit != s.hit)
            {
               s.hit = hit;
               if(hit != 0 && p.method_503() && n == 2)
               {
                  onHit(legends[1 - i],1 - i,s,i,p,hit);
               }
            }
         }
         if(result != null && !result.done)
         {
            settle(frame);
         }
         draw(core,now);
      }

      private static function trackMoves(s:Object, i:int, p:Object, frame:uint) : void
      {
         var main:Object = p.var_2000.var_9222;
         if(main != null && uint(main.var_13001) == 0)
         {
            main = null;
         }
         var until:uint = main != null ? uint(main.var_402) : 0;
         var seq:Object = s.seq;
         if(main != null && seq == null && s.ended != null && followsUp(s.ended,main.var_14247,frame))
         {
            seq = s.seq = s.ended;
            seq.end = 0;
         }
         if(main != null)
         {
            if(seq == null)
            {
               seq = s.seq = {"who":i,"start":uint(main.var_13001),"powers":[],"seen":new Dictionary(true),"until":0,
                  "end":0,"hit":false};
               last = seq;
            }
            if(seq.seen[main] == null)
            {
               seq.seen[main] = true;
               seq.powers.push(main.var_14247);
               seq.cur = main.var_14247;
               seq.curStart = uint(main.var_13001);
               if(ModSettings.value("frameDataLog") == true)
               {
                  Platform.log("frame data: P" + (i + 1) + " starts " + main.var_14247.var_504 + " at " + main.var_13001 +
                     " (seen " + frame + "), recovery end " + main.var_402 + ", combo " + main.var_14247.var_3463);
               }
            }
            if(until != 0)
            {
               seq.until = until;
            }
         }
         else if(seq != null)
         {
            seq.end = seq.until != 0 && seq.until <= frame ? seq.until : frame;
            s.seq = null;
            s.ended = seq;
            if(ModSettings.value("frameDataLog") == true)
            {
               Platform.log("frame data: P" + (i + 1) + " " + names(seq) + " frames " + seq.start + "-" + seq.end +
                  " (recovery end " + seq.until + ", seen ended " + frame + ")" + (seq.hit ? " hit" : ""));
            }
         }
      }

      private static function followsUp(seq:Object, next:Object, frame:uint) : Boolean
      {
         var prev:Object = seq.powers[seq.powers.length - 1];
         if(frame > uint(seq.end) + 2)
         {
            return false;
         }
         var name:String = String(next.var_504);
         if(name == prev.var_3463 || name == prev.var_7476 || name == prev.var_2949 || name == prev.var_4757 ||
            name == prev.var_12573)
         {
            return true;
         }
         return false;
      }

      private static function onHit(a:Object, ai:int, d:Object, di:int, victim:Object, hit:uint) : void
      {
         if(result != null)
         {
            recent.unshift((result.power != null ? String(result.power.var_504) : "?") + "  " +
               (result.done ? signed(result.advantage) + (result.seq == null ? " (?)" : "") : result.victimFree == 0 ? "combo" : "?") +
               (result.combo > 1 ? "  x" + result.combo : ""));
            if(recent.length > RECENT)
            {
               recent.length = RECENT;
            }
         }
         var seq:Object = a != null ? (a.seq != null ? a.seq : (last != null && last.who == ai ? last : null)) : null;
         var combo:int = 1;
         if(result != null && result.attacker == ai && result.victim == di && !result.victimFree)
         {
            combo = result.combo + 1;
         }
         var hitFrame:int = seq != null ? int(hit / STEP) - int(seq.curStart) + 1 : 0;
         if(seq != null)
         {
            seq.hit = true;
         }
         result = {"attacker":ai,"victim":di,"seq":seq,"player":victim,"at":hit,"hitFrame":hitFrame,
            "power":seq != null ? seq.cur : null,
            "stun":uint(victim.var_9413) / STEP,"combo":combo,"victimFree":0,"attackerFree":0,"done":false,
            "advantage":0};
      }

      private static function settle(frame:uint) : void
      {
         var r:Object = result;
         var victim:Object = r.player;
         if(r.victimFree == 0 && (!victim.method_503() || uint(victim.var_8895) != r.at))
         {
            var ended:uint = uint(victim.var_4497);
            r.victimFree = ended >= r.at ? ended / STEP : frame;
         }
         if(r.attackerFree == 0 && r.seq != null && r.seq.end != 0 && frame > uint(r.seq.end) + 2)
         {
            r.attackerFree = r.seq.end;
         }
         if(r.victimFree != 0 && (r.attackerFree != 0 || r.seq == null))
         {
            r.done = true;
            if(ModSettings.value("frameDataLog") == true)
            {
               Platform.log("frame data: hit at " + (r.at / STEP) + " stun " + r.stun + " victim free " + r.victimFree +
                  " attacker free " + r.attackerFree);
            }
            r.advantage = r.seq != null ? int(r.victimFree) - int(r.attackerFree) : 0;
            lastLine = names(r.seq) + " hit " + (r.power != null ? r.power.var_504 + " frame " : "") + r.hitFrame + " stun " + r.stun + " adv " + r.advantage + " combo " + r.combo;
            Platform.log("frame data: " + lastLine);
         }
      }

      private static function names(seq:Object) : String
      {
         if(seq == null)
         {
            return "?";
         }
         var out:Array = [];
         for each(var t:Object in seq.powers)
         {
            out.push(String(t.var_504));
         }
         return out.join(" > ");
      }

      private static function signed(v:int) : String
      {
         return v > 0 ? "+" + v : String(v);
      }

      private static function draw(core:Object, now:uint) : void
      {
         if(BigWindow.anyOpen() || LoadingBackground.showing)
         {
            if(root != null && root.parent != null)
            {
               root.parent.removeChild(root);
            }
            shown = "";
            return;
         }
         var lines:Array = [];
         var seq:Object = last;
         if(seq == null)
         {
            lines.push("FRAME DATA  (Ctrl+F1 to hide)");
            lines.push("Use a move to see its numbers.");
         }
         else
         {
            lines.push((seq.who == 0 ? "P1  " : "P" + (seq.who + 1) + "  ") + names(seq));
            var t:Object = result != null && result.seq == seq && result.power != null ? result.power : seq.powers[0];
            var startup:uint = t.var_13330 != null && t.var_13330.length > 0 ? uint(t.var_13330[0]) : 0;
            lines.push(String(t.var_504) + ": startup " + startup + "  recovery " + (uint(t.var_6131) + uint(t.var_13412)) + "  cooldown " +
               uint(t.var_11660) + "  stun " + uint(t.var_3066));
            if(seq.end != 0)
            {
               lines.push("Length " + (int(seq.end) - int(seq.start)) + " frames" + (seq.hit ? "" : "  (no hit)"));
            }
            else
            {
               lines.push("Length ...");
            }
         }
         var r:Object = result;
         if(r != null)
         {
            var head:String = "Hit on frame " + r.hitFrame + (r.power != null ? " of " + r.power.var_504 : "") + "  stun " + r.stun + (r.combo > 1 ? "  COMBO x" + r.combo : "");
            lines.push(head);
            if(r.done)
            {
               lines.push("Advantage " + signed(r.advantage) + (r.seq == null ? " (?)" : ""));
            }
            else
            {
               var left:int = Math.ceil((int(r.at) + int(r.stun) * STEP - int(now) - int(STEP)) / STEP);
               lines.push(r.victimFree != 0 ? "Advantage ... (attacker still busy)" :
                  left > 0 ? "Hitstun left " + left : "Hitstun held (still flying)");
            }
         }
         if(recent.length > 0)
         {
            lines.push("Hits before (advantage):");
            for each(var past:String in recent)
            {
               lines.push("   " + past);
            }
         }
         var s:String = lines.join("\n");
         if(root == null)
         {
            root = new Sprite();
            root.mouseEnabled = root.mouseChildren = false;
            panel = new Sprite();
            root.addChild(panel);
            field = UiKit.text(panel,"",10,6,13,UiKit.WHITE,UiKit.BOLD,360);
         }
         if(root.parent == null)
         {
            shown = "";
         }
         Layers.put(root,Layers.screens(),stage,true);
         if(s != shown)
         {
            shown = s;
            field.text = s;
            panel.graphics.clear();
            panel.graphics.beginFill(0x000000,0.55);
            panel.graphics.drawRoundRect(0,0,field.width + 20,field.height + 12,10,10);
            panel.graphics.endFill();
         }
         panel.x = stage.stageWidth - panel.width - 16;
         panel.y = Math.round(stage.stageHeight * 0.3);
      }
   }
}
