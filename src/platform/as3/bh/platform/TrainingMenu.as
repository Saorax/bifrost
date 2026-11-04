package bh.platform
{
   public final class TrainingMenu
   {
      public static const FIRST:int = 100;

      private static var rows:Array = null;

      public function TrainingMenu()
      {
      }

      public static function init() : void
      {
         Hooks.trainingMenuBuilt.add(build);
         Hooks.trainingRowState.add(state);
         Hooks.trainingRowValue.add(value);
         Hooks.trainingRowChange.add(change);
      }

      private static function defs() : Array
      {
         if(rows != null)
         {
            return rows;
         }
         rows = [
            {"name":"Player_BhFrameData","label":"Frame Data (Ctrl+F1)","values":["Off","On"],
               "get":function():int { return FrameData.on ? 1 : 0; },
               "set":function(i:int):void { FrameData.on = i == 1; }},
            {"name":"Player_BhHitboxTrail","label":"Hitbox Trail (Ctrl+F3)","values":["Off","On"],
               "get":function():int { return HitboxTrail.on ? 1 : 0; },
               "set":function(i:int):void { HitboxTrail.on = i == 1; }},
            {"name":"Bot_BhDrift","label":"Bot DI and Drift (Ctrl+F4)","values":DummyDrift.NAMES,
               "get":function():int { return DummyDrift.mode; },
               "set":function(i:int):void { DummyDrift.mode = i; }},
            {"name":"Bot_BhRecovery","label":"Bot Recovery (Shift+F4)","values":DummyRecovery.NAMES,
               "get":function():int { return DummyRecovery.mode; },
               "set":function(i:int):void { DummyRecovery.mode = i; }},
            {"name":"Player_BhStateSlot","label":"Saved State Slot (F1 / F2)","values":[],"refresh":stateSlotNames,
               "get":function():int { return TrainingState.slot; },
               "set":function(i:int):void { TrainingState.slot = i; }},
            {"name":"Bot_BhDummySlot","label":"Recording Slot","values":[],"refresh":slotNames,
               "get":function():int { return TrainingDummy.slot; },
               "set":function(i:int):void { TrainingDummy.slot = i; }}];
         for(var i:int = 0; i < rows.length; i++)
         {
            rows[i].index = FIRST + i;
            rows[i].enumValue = null;
            if(rows[i].refresh != null)
            {
               rows[i].values = rows[i].refresh();
            }
         }
         return rows;
      }

      private static function stateSlotNames() : Array
      {
         var out:Array = [];
         for(var i:int = 0; i < TrainingState.SLOTS; i++)
         {
            out.push("Slot " + (i + 1) + "  (" + TrainingState.describeSlot(i) + ")");
         }
         return out;
      }

      private static function slotNames() : Array
      {
         var out:Array = [];
         for(var i:int = 0; i < TrainingDummy.SLOTS; i++)
         {
            out.push("Slot " + (i + 1) + "  (" + TrainingDummy.slotSummary(i) + ")");
         }
         return out;
      }

      private static function labelKey(d:Object) : String
      {
         return "BH_TrainingSettings_" + d.name;
      }

      private static function valueKey(d:Object, i:int) : String
      {
         return "BH_TrainingSettings_" + d.name + "_" + i;
      }

      private static function registerNames() : void
      {
         try
         {
            var table:Object = class_256.var_5943.var_15061;
            for each(var d:Object in defs())
            {
               if(d.refresh != null)
               {
                  d.values = d.refresh();
               }
               table.method_65(labelKey(d),d.label);
               for(var i:int = 0; i < d.values.length; i++)
               {
                  table.method_65(valueKey(d,i),d.values[i]);
               }
            }
         }
         catch(e:Error)
         {
            Platform.log("training menu (names): " + e.message);
         }
      }

      private static function find(row:Object) : Object
      {
         var e:Object = row != null ? row.var_5108 : null;
         if(e == null || int(e.index) < FIRST)
         {
            return null;
         }
         for each(var d:Object in defs())
         {
            if(d.index == int(e.index))
            {
               return d;
            }
         }
         return null;
      }

      private static function build(screen:Object) : void
      {
         try
         {
            registerNames();
            for each(var d:Object in defs())
            {
               d.enumValue = new class_549(d.name,d.index,null);
               screen.method_5946(d.enumValue,labelKey(d),4);
               screen.var_15010.push(d.enumValue);
            }
         }
         catch(e:Error)
         {
            Platform.log("training menu: " + e.getStackTrace());
         }
      }

      private static function state(screen:Object, row:Object) : Boolean
      {
         if(find(row) == null)
         {
            return false;
         }
         row.method_5050(true,false);
         return true;
      }

      private static function value(screen:Object, row:Object) : Boolean
      {
         var d:Object = find(row);
         if(d == null)
         {
            return false;
         }
         var i:int = int(d.get());
         if(i < 0 || i >= d.values.length)
         {
            i = 0;
         }
         row.method_823(valueKey(d,i));
         return true;
      }

      private static function change(screen:Object, row:Object, dir:int) : Boolean
      {
         var d:Object = find(row);
         if(d == null)
         {
            return false;
         }
         var n:int = d.values.length;
         var i:int = (int(d.get()) + (dir < 0 ? -1 : 1) + n) % n;
         d.set(i);
         if(d.refresh != null)
         {
            registerNames();
         }
         Platform.log("training menu: " + d.name + " = " + d.values[i]);
         return true;
      }

      public static function press(screen:Object, name:String, dir:int) : String
      {
         for each(var d:Object in defs())
         {
            if(d.name == name && d.enumValue != null)
            {
               var row:Object = screen.var_3041.method_4935(d.enumValue);
               if(row == null)
               {
                  return name + ": no row on this screen";
               }
               row.method_4842(dir);
               return name + " = " + d.values[int(d.get())];
            }
         }
         return name + ": no such row";
      }

      public static function describe() : String
      {
         var out:Array = [];
         for each(var d:Object in defs())
         {
            out.push(d.name + "=" + d.values[Math.max(0,Math.min(d.values.length - 1,int(d.get())))]);
         }
         return out.join("; ");
      }
   }
}
