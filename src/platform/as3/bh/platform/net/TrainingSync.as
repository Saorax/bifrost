package bh.platform.net
{
   import bh.platform.ErrorLog;
   import bh.platform.OnlineTraining;
   import bh.platform.TrainingState;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   public final class TrainingSync
   {
      public static const MARK:uint = 0x75;

      public static const LOOK_MARK:uint = 0x76;

      public static const PAUSE_MARK:uint = 0x77;

      private static var pauseClock:uint = 0;
      private static var pauseId:uint = 0;
      private static var pauseHold:int = -1;
      private static var pauseLateFor:uint = 0;
      private static var pauseNoteAt:int = 0;
      private static var pauseTop:int = -1;

      private static const BACK_LIMIT:int = 30000;

      public static var stepBacks:uint = 0;

      public static var pauseCommands:uint = 0;
      public static var pausedFrames:uint = 0;

      public static const LOOK:int = 255;

      private static const MAX_SEND:int = 16;

      private static var pending:Array = [];
      private static var outgoing:Array = [];
      private static var seen:Object = {};
      private static var seq:uint = 0;

      public static var applied:uint = 0;
      public static var lateCount:uint = 0;
      public static var heldFrames:uint = 0;

      public static var appliedAt:uint = 0;

      public function TrainingSync()
      {
      }

      public static function reset() : void
      {
         pending = [];
         outgoing = [];
         seen = {};
         seq = 0;
         applied = 0;
         lateCount = 0;
         heldFrames = 0;
         appliedAt = 0;
         pauseClock = pauseId = pauseLateFor = 0;
         pauseHold = pauseTop = -1;
         stepBacks = 0;
         pauseCommands = pausedFrames = 0;
      }

      public static function get paused() : Boolean
      {
         return pauseHold >= 0;
      }

      public static function pauseKey(core:Object, key:String, held:uint) : void
      {
         if(uint(core.var_5300) == 0)
         {
            return;
         }
         var start:Number = P2PSession.base(core);
         var hold:int;
         if(key == "F7")
         {
            hold = paused ? -1 : pauseTime(core,start);
         }
         else if(key == "F5" && paused)
         {
            if(held > 0 && (held < 600 || held < 1200 && int(Math.floor(held / 16)) % 2 != 0))
            {
               return;
            }
            var floor:Number = Math.max(16,Math.max(Number(appliedAt) - 16 - start,pauseTop - BACK_LIMIT));
            hold = pauseHold - 16;
            if(hold < floor)
            {
               TrainingState.show("Can't go further back");
               pauseNoteAt = getTimer();
               return;
            }
         }
         else
         {
            if(held > 0 && (held < 600 || held < 1200 && int(Math.floor(held / 16)) % 2 != 0))
            {
               return;
            }
            hold = paused ? int(Math.max(pauseHold,int(uint(core.var_13849) - start))) + 16 : pauseTime(core,start);
         }
         pauseClock++;
         pauseId = P2PSession.myId;
         setHold(hold);
         pauseCommands++;
         noteState();
         PrivateServer.log("P2P training " + (hold < 0 ? "runs on" : "holds at " + hold + " ms") + " (" + key + ", now " +
            (uint(core.var_12659) - start) + " ms, clock " + pauseClock + ")");
      }

      private static function pauseTime(core:Object, start:Number) : int
      {
         var t:uint = uint(Math.max(uint(core.var_12659),uint(core.var_13849))) + P2PSession.inputDelay + 96;
         return int(Math.ceil((t - start) / 16) * 16);
      }

      private static function hearPause(clock:uint, id:uint, hold:int) : void
      {
         if(clock > pauseClock || clock == pauseClock && id > pauseId)
         {
            pauseClock = clock;
            pauseId = id;
            setHold(hold);
            noteState();
            PrivateServer.log("P2P training " + (hold < 0 ? "runs on" : "holds at " + hold + " ms") + " from ID " + id +
               " (clock " + clock + ")");
         }
      }

      private static function setHold(hold:int) : void
      {
         pauseHold = hold;
         pauseTop = hold < 0 ? -1 : int(Math.max(pauseTop,hold));
      }

      private static function noteState() : void
      {
         pauseNoteAt = getTimer();
         try
         {
            TrainingState.show(pauseHold < 0 ? "Playing" : "Paused, frame " + int(pauseHold / 16) +
               "  (F7 to play, F6 next frame)");
         }
         catch(e:Error)
         {
         }
      }

      private static function holdPaused(core:Object, start:Number) : void
      {
         if(pauseHold < 0)
         {
            return;
         }
         if(getTimer() - pauseNoteAt > 1000)
         {
            noteState();
         }
         var at:uint = uint(start + pauseHold);
         var simulated:uint = uint(core.var_13849);
         if(simulated > at && at + 16 >= appliedAt && Number(at) >= start + 16 && simulated - at < 50000)
         {
            core.method_4383(at + 16);
            Smoothing.rollingBack();
            stepBacks++;
            simulated = at;
         }
         if(simulated > at)
         {
            if(pauseLateFor != pauseClock)
            {
               pauseLateFor = pauseClock;
               lateCount++;
               PrivateServer.log("P2P training pause late: holds at " + (simulated - start) + " ms, not " + pauseHold);
            }
            at = simulated;
         }
         if(uint(core.var_12659) > at)
         {
            core.var_12659 = at;
            if(simulated == at)
            {
               pausedFrames++;
            }
         }
      }

      public static function summary() : String
      {
         return "training changes: " + applied + " applied" + (lateCount > 0 ? ", " + lateCount + " late" : "") + ", held " +
            heldFrames + " frames" + (pauseClock > 0 ? ", paused " + pausedFrames + " frames, " + stepBacks + " back to the hold (" + pauseCommands +
            " pause keys here, clock " + pauseClock + (paused ? ", holding at " + pauseHold + " ms" : "") + ")" : "") + (pending.length > 0 ? ", " + pending.length + " waiting (next " + describe(pending[0]) +
            " at " + pending[0].t + " ms)" : "");
      }

      public static function get usable() : Boolean
      {
         return P2PSession.rollbackOn && OnlineTraining.active;
      }

      public static function queueLocal(core:Object, row:int, dir:int, look:Array = null) : void
      {
         if(uint(core.var_5300) == 0)
         {
            return;
         }
         var start:Number = P2PSession.base(core);
         var t:uint = uint(core.var_12659) + P2PSession.inputDelay + P2PSession.MAX_PREDICT + 32;
         t = uint(Math.ceil(t / 16) * 16);
         while((t / 16) % 5 != 1)
         {
            t += 16;
         }
         for each(var other:Object in pending)
         {
            t = Math.max(t,uint(start + int(other.t)));
         }
         var c:Object = {"t":int(t - start),"id":P2PSession.myId,"seq":++seq,"row":row,"dir":dir,"look":look};
         outgoing.push(c);
         add(c);
         PrivateServer.log("P2P training change: " + describe(c) + " at " + c.t + " ms (now " + (uint(core.var_12659) - start) +
            ")");
      }

      private static function describe(c:Object) : String
      {
         if(c.look == null && int(c.row) == TrainingState.SAVE_ROW)
         {
            return "save state (slot " + (int(c.dir) + 1) + ")";
         }
         if(c.look == null && int(c.row) == TrainingState.LOAD_ROW)
         {
            return "load state (slot " + (int(c.dir) + 1) + ")";
         }
         return c.look != null ? "look " + c.look.join(" ") : "row " + c.row + " " + c.dir;
      }

      private static function add(c:Object) : void
      {
         var key:String = c.id + ":" + c.seq;
         if(seen[key])
         {
            return;
         }
         seen[key] = true;
         pending.push(c);
         pending.sortOn(["t","id","seq"],Array.NUMERIC);
      }

      public static function handoffBy(time:uint, start:Number) : Boolean
      {
         for each(var c:Object in pending)
         {
            if(c.look == null && int(c.row) == OnlineTraining.CONTROL_ROW && start + int(c.t) <= time)
            {
               return true;
            }
         }
         return false;
      }

      public static function write(body:ByteArray, peers:Object) : void
      {
         while(outgoing.length > 0)
         {
            var all:Boolean = true;
            for each(var peer:Object in peers)
            {
               if(!peer.gone && int(peer.ack) < int(outgoing[0].t) - 16)
               {
                  all = false;
               }
            }
            if(!all)
            {
               break;
            }
            outgoing.shift();
         }
         var rows:Array = [];
         var looks:Array = [];
         for(var i:int = 0; i < outgoing.length && rows.length + looks.length < MAX_SEND; i++)
         {
            (outgoing[i].look != null ? looks : rows).push(outgoing[i]);
         }
         body.writeByte(MARK);
         body.writeByte(rows.length);
         for each(var c:Object in rows)
         {
            body.writeUnsignedInt(uint(c.t));
            body.writeUnsignedInt(uint(c.id));
            body.writeShort(c.seq);
            body.writeByte(c.row);
            body.writeByte(c.dir);
         }
         if(looks.length > 0)
         {
            writeLooks(body,looks);
         }
         if(pauseClock > 0)
         {
            body.writeByte(PAUSE_MARK);
            body.writeUnsignedInt(pauseClock);
            body.writeUnsignedInt(pauseId);
            body.writeInt(pauseHold);
         }
      }

      private static function writeLooks(body:ByteArray, looks:Array) : void
      {
         body.writeByte(LOOK_MARK);
         body.writeByte(looks.length);
         for each(var c:Object in looks)
         {
            body.writeUnsignedInt(uint(c.t));
            body.writeUnsignedInt(uint(c.id));
            body.writeShort(c.seq);
            body.writeByte(c.look[0]);
            for(var k:int = 1; k < 6; k++)
            {
               body.writeShort(c.look[k]);
            }
         }
      }

      public static function read(b:ByteArray) : void
      {
         if(b.bytesAvailable < 2 || b.readUnsignedByte() != MARK)
         {
            return;
         }
         var n:int = b.readUnsignedByte();
         for(var i:int = 0; i < n && b.bytesAvailable >= 12; i++)
         {
            var c:Object = {"t":int(b.readUnsignedInt()),"id":b.readUnsignedInt(),"seq":b.readUnsignedShort(),
               "row":b.readUnsignedByte(),"dir":b.readByte()};
            add(c);
         }
         if(b.bytesAvailable < 2)
         {
            return;
         }
         var mark:uint = b.readUnsignedByte();
         if(mark == LOOK_MARK)
         {
            readLooks(b);
            if(b.bytesAvailable < 13)
            {
               return;
            }
            mark = b.readUnsignedByte();
         }
         if(mark == PAUSE_MARK && b.bytesAvailable >= 12)
         {
            var clock:uint = b.readUnsignedInt();
            var id:uint = b.readUnsignedInt();
            hearPause(clock,id,b.readInt());
         }
      }

      private static function readLooks(b:ByteArray) : void
      {
         var n:int = b.readUnsignedByte();
         for(var i:int = 0; i < n && b.bytesAvailable >= 21; i++)
         {
            var c:Object = {"t":int(b.readUnsignedInt()),"id":b.readUnsignedInt(),"seq":b.readUnsignedShort(),"row":LOOK,"dir":0};
            var look:Array = [b.readUnsignedByte()];
            for(var k:int = 1; k < 6; k++)
            {
               look.push(b.readUnsignedShort());
            }
            c.look = look;
            add(c);
         }
      }

      public static function frame(core:Object, start:Number, late:uint, fed:Number) : void
      {
         if(!applyDue(core,start,late,fed))
         {
            holdPaused(core,start);
         }
      }

      private static function applyDue(core:Object, start:Number, late:uint, fed:Number) : Boolean
      {
         while(pending.length > 0)
         {
            var c:Object = pending[0];
            var at:uint = uint(start + int(c.t));
            var simulated:uint = uint(core.var_13849);
            if(simulated > at - 16)
            {
               lateCount++;
               ErrorLog.write("P2P training change late: " + describe(c) + " for " + c.t + " ms, match already at " +
                  (simulated - start) + " ms (the PCs may split)");
            }
            else if(simulated < at - 16 || fed < Number(c.t) - 16 || (late != uint.MAX_VALUE && late < at))
            {
               if(uint(core.var_12659) > at - 16)
               {
                  core.var_12659 = at - 16;
                  if(simulated == at - 16)
                  {
                     heldFrames++;
                  }
               }
               return false;
            }
            pending.shift();
            var target:uint = uint(core.var_12659);
            core.var_12659 = at - 16;
            var loadedTo:Number = -1;
            try
            {
               if(c.look != null)
               {
                  OnlineTraining.applyLook(core,c.look,uint(c.id));
               }
               else if(int(c.row) == TrainingState.SAVE_ROW)
               {
                  TrainingState.saveOnline(core,at,int(c.dir));
               }
               else if(int(c.row) == TrainingState.LOAD_ROW)
               {
                  loadedTo = TrainingState.loadOnline(core,at,target,int(c.dir));
               }
               else
               {
                  OnlineTraining.applyRow(core,int(c.row),int(c.dir),uint(c.id));
               }
               applied++;
               appliedAt = at;
            }
            catch(e:*)
            {
               ErrorLog.write("P2P training change: " + e + " " + (e is Error ? Error(e).getStackTrace() : ""));
            }
            core.var_12659 = target;
            PrivateServer.log("P2P training change applied: " + describe(c) + " from ID " + c.id + " at " + c.t + " ms");
            if(loadedTo >= 0)
            {
               core.var_12659 = uint(loadedTo);
               appliedAt = TrainingState.loadedAt;
               return true;
            }
         }
         return false;
      }
   }
}
