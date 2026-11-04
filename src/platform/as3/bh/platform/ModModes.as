package bh.platform
{
   public final class ModModes
   {
      public static var rules:Object = {};

      private static var types:Object = {};

      private static var factories:Object = {};

      public static function registerRules(scoringName:String, factory:Function) : void
      {
         factories[scoringName] = factory;
         Platform.log("mode " + scoringName + ": rules registered by a code mod");
      }

      public static function init() : void
      {
         Hooks.tableParsing.add(tableParsing);
         Hooks.dataCheckFailed.add(waiveCheck);
      }

      private static function tableParsing(tableName:String, root:Object) : void
      {
         if(tableName != "ScoringTypes")
         {
            return;
         }
         var table:Object = ContentMods.added["ScoringTypes"] || {};
         for each(var mod:Object in ContentMods.mods)
         {
            for each(var row:* in (mod.tables != null ? mod.tables["ScoringTypes"] : null))
            {
               if(!(row is String) && row.copy is String && row.set != null && row.set["@ScoringName"] != null &&
                  table[String(row.set["@ScoringName"])] != null)
               {
                  rules[String(row.set["@ScoringName"])] = String(row.copy);
               }
            }
         }
         for(var name:String in table)
         {
            ContentMods.report.push("mode " + name + " (added by " + table[name] + "): plays with the rules of " +
               (rules[name] != null ? rules[name] : "a plain stock or timed mode"));
         }
      }

      private static function waiveCheck(message:String) : Boolean
      {
         var m:Array = /^\[ScoringType\.hx\] Scoring Type (\S+) does not have a matching const ptr in the client\./.exec(message);
         return m != null && ContentMods.isAdded("ScoringTypes",m[1]);
      }

      public static function rulesType(manager:Object, type:ScoringType) : ScoringType
      {
         if(type == null)
         {
            return type;
         }
         var base:String = rules[type.var_12666];
         if(base == null)
         {
            return type;
         }
         if(types[base] === undefined)
         {
            types[base] = null;
            for each(var t:ScoringType in ScoringType.var_11790)
            {
               if(t.var_12666 == base)
               {
                  types[base] = t;
               }
            }
         }
         return types[base] != null ? types[base] : type;
      }

      public static function rulesCreated(manager:class_345) : void
      {
         var type:ScoringType = manager.owner.var_8999.var_615;
         var factory:Function = type != null ? factories[type.var_12666] : null;
         if(factory == null)
         {
            return;
         }
         try
         {
            var made:class_334 = factory(manager.owner) as class_334;
            if(made != null)
            {
               manager.var_1712 = made;
            }
         }
         catch(e:Error)
         {
            Platform.log("mode " + type.var_12666 + ": the code mod's rules failed, playing with the copied rules: " +
               e.getStackTrace());
         }
      }
   }
}
