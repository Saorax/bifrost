package bh.platform
{
   import flash.utils.describeType;

   public class LegendStats
   {
      public static const TABLE:String = "RuneTypes";
      public static const STATS:Array = [
         ["Strength","Strength","var_692","Knockback the legend's hits give (StatTypes ImpulseMult, class_79.method_783)."],
         ["Dexterity","Dexterity","var_202","Recovery after moves, signature recovery and charge, weapon wear (StatTypes RecoverMod, " +
            "SigRecoverMod, MinChargeMod, DurabilityMod)."],
         ["Weight","Defense","var_3217","How fast knockback wears off: higher flies less far (StatTypes Recovery; \"Weight\" in " +
            "the game's table)."],
         ["Speed","Speed","var_6905","Run and air speed, acceleration, friction and animation speed (StatTypes)."]];
      public static const POINTS_TABLE:String = "StatTypes";
      public static const POINT_FIELDS:Object = {
         "ImpulseMult":"Knockback the legend's hits give, as a multiplier.",
         "RecoverMod":"Recovery after moves on the ground: the game divides recovery by it.",
         "AirRecoverMod":"Recovery after moves in the air: the game divides recovery by it.",
         "SigRecoverMod":"Recovery after signatures: the game divides it by this.",
         "MinChargeMod":"Minimum charge of charged moves: the game divides it by this.",
         "DurabilityMod":"How fast thrown and held weapons wear.",
         "Recovery":"How much knockback speed wears off each step (higher: flies less far).",
         "RunSpeed":"Top run speed.",
         "JumpXImpulse":"Sideways speed of a jump.",
         "AnimSpeed":"Animation speed of running.",
         "Acceleration":"Acceleration on the ground.",
         "Friction":"Slowing down on the ground.",
         "AirRunSpeed":"Top speed in the air.",
         "AirAcceleration":"Acceleration in the air.",
         "AirFriction":"Slowing down in the air.",
         "DamageFixed":"Fixed damage added.",
         "HPOffset":"Damage taken counted as this much more.",
         "ImpulseNegation":"Knockback taken away from every hit.",
         "InterruptThreshold":"Damage needed to interrupt."};
      private static var pristinePoints:Object = null;
      private static var loadedPoints:Object = null;
      private static var livePoints:Object = {};
      public static const MAX:int = 11;

      private static var pristine:Object = null;
      private static var live:Object = {};

      public static function init() : void
      {
         Hooks.tableParsing.add(function(table:String, root:Object):void
         {
            if(table == POINTS_TABLE)
            {
               pristinePoints = readPoints(root as Xml);
            }
            if(table == TABLE)
            {
               try
               {
                  pristine = read(root as Xml);
                  live = {};
               }
               catch(e:Error)
               {
                  ErrorLog.write("legend stats: RuneTypes unreadable: " + e);
               }
            }
         });
      }

      public static function initLoaded() : void
      {
         Hooks.tableParsing.add(function(table:String, root:Object):void
         {
            if(table == POINTS_TABLE)
            {
               loadedPoints = readPoints(root as Xml);
               livePoints = {};
            }
         });
      }

      private static function elements(node:Xml) : Array
      {
         var out:Array = [];
         for each(var child:Xml in node.var_5236)
         {
            if(child.var_14625 == Xml.var_11889)
            {
               out.push(child);
            }
         }
         return out;
      }

      private static function textOf(node:Xml) : String
      {
         var out:String = "";
         for each(var child:Xml in node.var_5236)
         {
            if(child.var_14625 != Xml.var_11889 && child.var_3342 != null)
            {
               out += child.var_3342;
            }
         }
         return out;
      }

      private static function readPoints(root:Xml) : Object
      {
         var out:Object = {};
         try
         {
            for each(var r:Xml in elements(root))
            {
               var name:String = r.method_4935("StatName");
               if(name == null || name == "Template")
               {
                  continue;
               }
               var fields:Object = {};
               for each(var f:Xml in elements(r))
               {
                  fields[f.var_4402] = textOf(f);
               }
               out[name] = fields;
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("legend stats: StatTypes unreadable: " + e);
         }
         return out;
      }

      private static function read(root:Xml) : Object
      {
         var out:Object = {};
         var hero:String = null;
         for each(var r:Xml in elements(root))
         {
            var fields:Object = {};
            for each(var f:Xml in elements(r))
            {
               fields[f.var_4402] = textOf(f);
            }
            if(fields.HeroName != null)
            {
               hero = fields.HeroName;
            }
            if(hero == null || fields.RuneIndex == null)
            {
               continue;
            }
            if(out[hero] == null)
            {
               out[hero] = {};
            }
            var values:Object = {};
            for each(var s:Array in STATS)
            {
               values[s[0]] = String(int(fields[s[0]]));
            }
            out[hero][String(int(fields.RuneIndex))] = values;
         }
         return out;
      }

      public static function legends() : Array
      {
         var out:Array = [];
         try
         {
            for each(var h:HeroType in HeroType.var_1273)
            {
               if(h != null && h.mHeroName != null && class_356.method_285(h.mHeroName) != null && out.indexOf(h.mHeroName) < 0)
               {
                  out.push(h.mHeroName);
               }
            }
         }
         catch(e:Error)
         {
         }
         out.sort(function(a:String, b:String):int
         {
            var x:String = displayName(a).toLowerCase();
            var y:String = displayName(b).toLowerCase();
            return x < y ? -1 : (x > y ? 1 : 0);
         });
         return out;
      }

      public static function displayName(hero:String) : String
      {
         try
         {
            for each(var h:HeroType in HeroType.var_1273)
            {
               if(h != null && h.mHeroName == hero)
               {
                  var shown:String = class_256.method_1351(h.mDisplayName);
                  return shown != null && shown != "" ? shown : hero;
               }
            }
         }
         catch(e:Error)
         {
         }
         return hero;
      }

      public static function stances(hero:String) : Array
      {
         var out:Array = [];
         var v:Vector.<class_356> = class_356.method_285(hero);
         if(v != null)
         {
            for(var i:int = 0; i < v.length; i++)
            {
               if(v[i] != null)
               {
                  out.push([i,v[i]]);
               }
            }
         }
         return out;
      }

      public static function stanceName(stance:class_356) : String
      {
         var icon:String = String(stance.var_2697);
         var name:String = icon.replace(/^a_StanceIcon_?/,"").replace(/([a-z])([A-Z])/g,"$1 $2");
         name = name == "Weight" ? "Defense" : name.replace("Super Weight","Super Defense");
         return name == "" || name == "null" ? "STANCE " + stance.var_3173 : name.toUpperCase();
      }

      public static function value(hero:String, index:int, col:String) : int
      {
         var s:class_356 = stance(hero,index);
         return s == null ? 0 : int(s[field(col)]);
      }

      public static function gameValue(hero:String, index:int, col:String) : int
      {
         var p:Object = pristine != null && pristine[hero] != null ? pristine[hero][String(index)] : null;
         return p != null && p[col] != null ? int(p[col]) : value(hero,index,col);
      }

      private static function stance(hero:String, index:int) : class_356
      {
         var v:Vector.<class_356> = class_356.method_285(hero);
         return v != null && index >= 0 && index < v.length ? v[index] : null;
      }

      private static function field(col:String) : String
      {
         for each(var s:Array in STATS)
         {
            if(s[0] == col)
            {
               return s[2];
            }
         }
         return null;
      }

      public static function apply(hero:String, index:int, col:String, n:int) : String
      {
         var s:class_356 = stance(hero,index);
         if(s == null || field(col) == null)
         {
            return "No " + col + " for " + hero + " stance " + index + ".";
         }
         if(n < 0 || n > MAX)
         {
            return "Stats go from 0 to " + MAX + ".";
         }
         s[field(col)] = uint(n);
         if(live[hero] == null)
         {
            live[hero] = {};
         }
         if(live[hero][String(index)] == null)
         {
            live[hero][String(index)] = {};
         }
         live[hero][String(index)][col] = String(n);
         refresh(hero,index);
         return "";
      }

      public static function refresh(hero:String, index:int) : int
      {
         var n:int = 0;
         try
         {
            var players:Object = ScreenManager.owner != null ? ScreenManager.owner.var_7050 : null;
            for(var i:int = 0; players != null && i < players.length; i++)
            {
               var p:class_123 = players[i];
               if(p != null && p.var_13881 != null && p.var_13881.mHeroName == hero && int(p.var_3173) == index)
               {
                  p.method_1870(p.var_13881,p.var_3173);
                  n++;
               }
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("legend stats: refresh failed: " + e);
         }
         return n;
      }

      public static function current() : Array
      {
         try
         {
            var players:Object = ScreenManager.owner.var_7050;
            if(players != null && players.length > 0 && players[0].var_13881 != null)
            {
               return [String(players[0].var_13881.mHeroName),int(players[0].var_3173)];
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function playersText() : String
      {
         var out:Array = [];
         try
         {
            var players:Object = ScreenManager.owner.var_7050;
            for(var i:int = 0; i < players.length; i++)
            {
               var p:class_123 = players[i];
               out.push("p" + i + " " + (p.var_13881 != null ? p.var_13881.mHeroName : "?") + "/" + p.var_3173 + " str " +
                  p.var_5999 + " dex " + p.var_14833 + " def " + p.var_7615 + " spd " + p.var_2956 + " (run " + p.var_2921 + ")");
            }
         }
         catch(e:Error)
         {
            out.push("(" + e + ")");
         }
         return out.join(", ");
      }

      public static function savedIn(tables:Object) : Object
      {
         var out:Object = {};
         for each(var row:Object in tables != null ? tables[TABLE] : null)
         {
            if(row != null && row.stance is String && row.set != null)
            {
               if(out[row.stance] == null)
               {
                  out[row.stance] = {};
               }
               out[row.stance][String(row.index)] = row.set;
            }
         }
         return out;
      }

      public static function changes(saved:Object) : Object
      {
         var all:Object = saved;
         for(var hero:String in live)
         {
            for(var idx:String in live[hero])
            {
               if(all[hero] == null)
               {
                  all[hero] = {};
               }
               if(all[hero][idx] == null)
               {
                  all[hero][idx] = {};
               }
               for(var col:String in live[hero][idx])
               {
                  all[hero][idx][col] = live[hero][idx][col];
               }
            }
         }
         for(hero in all)
         {
            var stancesLeft:int = 0;
            for(idx in all[hero])
            {
               var left:int = 0;
               for(col in all[hero][idx])
               {
                  if(int(all[hero][idx][col]) == gameValue(hero,int(idx),col))
                  {
                     delete all[hero][idx][col];
                  }
                  else
                  {
                     left++;
                  }
               }
               if(left == 0)
               {
                  delete all[hero][idx];
               }
               else
               {
                  stancesLeft++;
               }
            }
            if(stancesLeft == 0)
            {
               delete all[hero];
            }
         }
         return all;
      }

      public static function rows(changed:Object) : Array
      {
         var out:Array = [];
         var heroes:Array = [];
         for(var hero:String in changed)
         {
            heroes.push(hero);
         }
         heroes.sort();
         for each(hero in heroes)
         {
            var idxs:Array = [];
            for(var idx:String in changed[hero])
            {
               idxs.push(int(idx));
            }
            idxs.sort(Array.NUMERIC);
            for each(var i:int in idxs)
            {
               out.push({"stance":hero,"index":i,"set":changed[hero][String(i)]});
            }
         }
         return out;
      }

      public static function pointRow(row:String) : Object
      {
         var out:Object = {};
         var base:Object = loadedPoints != null ? loadedPoints[row] : null;
         for(var k:String in base)
         {
            out[k] = base[k];
         }
         for(k in livePoints[row])
         {
            out[k] = livePoints[row][k];
         }
         return out;
      }

      public static function gamePoint(row:String, col:String) : String
      {
         var p:Object = pristinePoints != null ? pristinePoints[row] : null;
         return p != null && p[col] != null ? String(p[col]) : null;
      }

      public static function applyPoint(row:String, col:String, value:String) : String
      {
         if(POINT_FIELDS[col] == null)
         {
            return "StatTypes has no column " + col + ".";
         }
         if(!/^-?\d+(\.\d+)?$/.test(value))
         {
            return "Type a number.";
         }
         if(/Mod$/.test(col) && col != "DurabilityMod" && Number(value) == 0)
         {
            return col + " can't be 0 (the game divides by it).";
         }
         var target:class_583 = class_583.method_931(row);
         if(target == null || loadedPoints == null || loadedPoints[row] == null)
         {
            return "No stat row " + row + ".";
         }
         var fields:Object = pointRow(row);
         fields[col] = value;
         var xml:String = "<StatType StatName=\"" + row + "\">";
         for(var k:String in fields)
         {
            xml += "<" + k + ">" + fields[k] + "</" + k + ">";
         }
         xml += "</StatType>";
         var map:Object = Object(class_583.var_4552).h;
         var list:Array = class_583.var_14813;
         var count:int = list.length;
         var fresh:class_583 = null;
         try
         {
            delete map[row];
            class_583.method_4149(Xml.parse(xml).method_7292());
            fresh = map[row];
         }
         catch(e:Error)
         {
            ErrorLog.write("legend stats: StatTypes parse failed: " + e);
         }
         finally
         {
            map[row] = target;
            list.length = count;
         }
         if(fresh == null)
         {
            return "The game refused " + col + " " + value + ".";
         }
         for each(var v:XML in describeType(target).variable)
         {
            var name:String = String(v.@name);
            target[name] = fresh[name];
         }
         if(livePoints[row] == null)
         {
            livePoints[row] = {};
         }
         livePoints[row][col] = value;
         refreshAll();
         return "";
      }

      public static function refreshAll() : int
      {
         var n:int = 0;
         try
         {
            var players:Object = ScreenManager.owner != null ? ScreenManager.owner.var_7050 : null;
            for(var i:int = 0; players != null && i < players.length; i++)
            {
               var p:class_123 = players[i];
               if(p != null && p.var_13881 != null)
               {
                  p.method_1870(p.var_13881,p.var_3173);
                  n++;
               }
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("legend stats: refresh failed: " + e);
         }
         return n;
      }

      public static function savedPointsIn(tables:Object) : Object
      {
         var out:Object = {};
         for each(var r:Object in tables != null ? tables[POINTS_TABLE] : null)
         {
            if(r != null && r.copy is String && r.set != null)
            {
               out[r.copy] = r.set;
            }
         }
         return out;
      }

      public static function pointChanges(saved:Object) : Object
      {
         var all:Object = saved;
         for(var row:String in livePoints)
         {
            if(all[row] == null)
            {
               all[row] = {};
            }
            for(var col:String in livePoints[row])
            {
               all[row][col] = livePoints[row][col];
            }
         }
         for(row in all)
         {
            var left:int = 0;
            for(col in all[row])
            {
               var game:String = gamePoint(row,col);
               if(game != null && Number(game) == Number(all[row][col]))
               {
                  delete all[row][col];
               }
               else
               {
                  left++;
               }
            }
            if(left == 0)
            {
               delete all[row];
            }
         }
         return all;
      }

      public static function pointRows(changed:Object) : Array
      {
         var names:Array = [];
         for(var row:String in changed)
         {
            names.push(row);
         }
         names.sort();
         var out:Array = [];
         for each(row in names)
         {
            out.push({"copy":row,"set":changed[row]});
         }
         return out;
      }

      public static function resetPoint(row:String) : String
      {
         var cur:Object = pointRow(row);
         for(var col:String in cur)
         {
            var game:String = gamePoint(row,col);
            if(game != null && game != cur[col])
            {
               var why:String = applyPoint(row,col,game);
               if(why != "")
               {
                  return why;
               }
            }
         }
         return "";
      }

      public static function reset(hero:String, index:int) : String
      {
         for each(var s:Array in STATS)
         {
            var why:String = apply(hero,index,s[0],gameValue(hero,index,s[0]));
            if(why != "")
            {
               return why;
            }
         }
         return "";
      }
   }
}
