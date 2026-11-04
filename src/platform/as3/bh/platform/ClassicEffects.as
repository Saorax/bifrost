package bh.platform
{
   import haxe.ds.IntMap;

   public final class ClassicEffects
   {
      private static var classic:Boolean = false;
      private static var kept:Array = [];
      private static var swaps:Array = null;
      private static var seen:int = -1;
      private static var keepSet:Object = null;
      private static var names:Object = null;
      private static var skinGroups:Array = null;
      private static var weaponGroups:Array = null;
      private static var artKept:Array = [];
      private static var inMatch:Boolean = false;

      private static const REPLAY:uint = 5;

      public static var stripped:int = 0;
      public static var swapsKept:int = 0;
      public static var swapsDropped:int = 0;

      public static function init() : void
      {
         classic = ModSettings.flag("classicEffects",false);
         Hooks.gameStateChanging.add(function(from:uint, to:uint):void
         {
            inMatch = to == Platform.MATCH_RUNNING || to == REPLAY;
            sync();
         });
      }

      private static function sync() : void
      {
         apply();
         if(classic && inMatch)
         {
            stripArt();
         }
         else
         {
            restoreArt();
         }
      }

      private static function stripArt() : void
      {
         if(artKept.length > 0)
         {
            return;
         }
         for each(var c:CostumeType in CostumeType.var_12012)
         {
            if(c != null && c.var_7606 != null && !swapped("c",c.mCostumeName))
            {
               artKept.push([c,c.var_7606]);
               c.var_7606 = null;
            }
         }
      }

      private static function restoreArt() : void
      {
         for each(var k:Array in artKept)
         {
            k[0].var_7606 = k[1];
         }
         artKept = [];
      }

      public static function get on() : Boolean
      {
         return classic;
      }

      public static function set on(v:Boolean) : void
      {
         classic = v;
         ModSettings.setFlag("classicEffects",v);
         restore();
         sync();
      }

      public static function swapped(kind:String, name:String) : Boolean
      {
         return keeps()[kind + ":" + name] == true;
      }

      public static function setSwapped(kind:String, list:Array, keep:Boolean) : void
      {
         var set:Object = keeps();
         for each(var name:String in list)
         {
            if(keep)
            {
               set[kind + ":" + name] = true;
            }
            else
            {
               delete set[kind + ":" + name];
            }
         }
         var saved:Array = [];
         for(var k:String in set)
         {
            saved.push(k);
         }
         saved.sort();
         ModSettings.setValue("classicEffectsKeep",saved);
         restore();
         sync();
      }

      public static function groups(weapons:Boolean) : Array
      {
         catalog();
         return weapons ? weaponGroups : skinGroups;
      }

      private static function keeps() : Object
      {
         if(keepSet == null)
         {
            keepSet = {};
            var v:* = ModSettings.value("classicEffectsKeep");
            if(v is Array)
            {
               for each(var s:String in v)
               {
                  keepSet[s] = true;
               }
            }
         }
         return keepSet;
      }

      private static function text(key:String, fallback:String) : String
      {
         try
         {
            var s:String = class_256.method_1351(key);
            if(s != null && s != "" && s != key)
            {
               return s;
            }
         }
         catch(e:Error)
         {
         }
         return fallback;
      }

      private static function count() : int
      {
         return (CostumeType.var_12012 != null ? CostumeType.var_12012.length : 0) +
            (class_725.var_6030 != null ? class_725.var_6030.length : 0);
      }

      private static function costumeNames() : Object
      {
         if(names == null)
         {
            names = {};
            for each(var c:CostumeType in CostumeType.var_12012)
            {
               if(c != null)
               {
                  names[c.var_14823] = c.mCostumeName;
               }
            }
         }
         return names;
      }

      private static function catalog() : void
      {
         if(skinGroups != null || count() == 0)
         {
            return;
         }
         var wasOn:Boolean = kept.length > 0 || swaps != null;
         restore();
         var ids:Object = {};
         ownedIds(class_306.var_5947,3,false,ids);
         ownedIds(class_306.var_4930,1,true,ids);
         skinGroups = [];
         for each(var h:HeroType in HeroType.var_12147)
         {
            if(h == null || h.var_10772 == null)
            {
               continue;
            }
            var skins:Array = [];
            for each(var c:CostumeType in h.var_10772)
            {
               if(c != null && ids[c.var_14823] == true)
               {
                  skins.push(["c",c.mCostumeName,text(c.mDisplayNameKey,c.mCostumeName),c]);
               }
            }
            if(skins.length > 0)
            {
               skinGroups.push([h.var_4421 ? String(h.var_4421) : text(h.mDisplayName,h.mHeroName),skins,h]);
            }
         }
         skinGroups.sort(byLabel);
         var byWeapon:Object = {};
         weaponGroups = [];
         for each(var w:class_725 in class_725.var_6030)
         {
            if(w == null || w.var_2682 == null && w.var_11437 == null)
            {
               continue;
            }
            var base:String = w.var_12803 != null ? w.var_12803 : "Other";
            if(byWeapon[base] == null)
            {
               byWeapon[base] = [base.toUpperCase(),[],null];
               weaponGroups.push(byWeapon[base]);
            }
            byWeapon[base][1].push(["w",w.mWeaponSkinName,text(w.mDisplayNameKey,w.mWeaponSkinName),w]);
         }
         weaponGroups.sort(byLabel);
         if(wasOn)
         {
            sync();
         }
      }

      private static function emote(swap:Object) : Boolean
      {
         var power:String = String(swap.var_5744);
         return power.indexOf("Taunt") >= 0 || power.indexOf("Emote") >= 0;
      }

      private static function byLabel(a:Array, b:Array) : int
      {
         return String(a[0]) < String(b[0]) ? -1 : (String(a[0]) > String(b[0]) ? 1 : 0);
      }

      private static function ownedIds(map:*, depth:int, asym:Boolean, out:Object) : void
      {
         if(map == null)
         {
            return;
         }
         for(var k:* in map.h)
         {
            var v:* = map.h[k];
            if(depth > 1)
            {
               ownedIds(v,depth - 1,asym,out);
            }
            else if(v != null && v.var_2748 == null && v.var_10786 == null && !emote(v))
            {
               out[asym ? uint(k) >>> 16 : uint(k)] = true;
            }
         }
      }

      private static function apply() : void
      {
         if(!classic)
         {
            restore();
            return;
         }
         var n:int = count();
         if(n == 0 || n == seen)
         {
            return;
         }
         restore();
         seen = n;
         for each(var c:CostumeType in CostumeType.var_12012)
         {
            if(c != null && !swapped("c",c.mCostumeName))
            {
               strip(c);
            }
         }
         for each(var w:class_725 in class_725.var_6030)
         {
            if(w != null && !swapped("w",w.mWeaponSkinName))
            {
               strip(w);
            }
         }
         stripped = kept.length;
         if(class_306.var_5947 != null)
         {
            swaps = [class_306.var_5947,class_306.var_4930];
            swapsKept = swapsDropped = 0;
            class_306.var_5947 = legendSwaps(swaps[0],3,false);
            class_306.var_4930 = legendSwaps(swaps[1],1,true);
         }
         Platform.log("skin effects: " + stripped + " skins and weapon skins lose their effect and sound overrides (and their swap art in matches); " + swapsDropped +
            " costume power swaps off, " + swapsKept + " legend, bot and chosen swaps kept");
      }

      private static function strip(o:Object) : void
      {
         if(o.var_2682 == null && o.var_11437 == null)
         {
            return;
         }
         kept.push([o,o.var_2682,o.var_11437,o.var_10517]);
         o.var_2682 = null;
         o.var_11437 = null;
         o.var_10517 = null;
      }

      private static function legendSwaps(map:*, depth:int, asym:Boolean) : *
      {
         var out:* = new IntMap();
         if(map == null)
         {
            return out;
         }
         for(var k:* in map.h)
         {
            var v:* = map.h[k];
            if(depth > 1)
            {
               var inner:* = legendSwaps(v,depth - 1,asym);
               var n:int = 0;
               for(var ik:* in inner.h)
               {
                  n++;
               }
               if(n > 0)
               {
                  out.h[k] = inner;
               }
            }
            else if(v != null && (v.var_2748 != null || v.var_10786 != null || emote(v) ||
               swapped("c",costumeNames()[asym ? uint(k) >>> 16 : uint(k)])))
            {
               out.h[k] = v;
               swapsKept++;
            }
            else
            {
               swapsDropped++;
            }
         }
         return out;
      }

      private static function restore() : void
      {
         for each(var k:Array in kept)
         {
            k[0].var_2682 = k[1];
            k[0].var_11437 = k[2];
            k[0].var_10517 = k[3];
         }
         kept = [];
         restoreArt();
         if(swaps != null)
         {
            class_306.var_5947 = swaps[0];
            class_306.var_4930 = swaps[1];
            swaps = null;
         }
         seen = -1;
         stripped = 0;
      }
   }
}
