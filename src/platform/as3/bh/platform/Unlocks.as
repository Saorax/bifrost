package bh.platform
{
   public class Unlocks
   {
      private static const NAME_FIELDS:Object = {"WeaponSkin": "mWeaponSkinName", "Avatar": "var_12772",
         "Taunt": "mTauntName", "Emoji": "var_1856", "KOEffect": "var_7437", "SpawnBot": "mSpawnBotName",
         "Border": "var_13754", "Podium": "mPodiumName", "PlayerTheme": "var_11826", "Companion": "var_3857",
         "Moniker": "var_5322", "EmitterGroup": "var_2065"};

      private static const DEVELOPER:String = "Developer";
      public static const PERKS:int = 11090;
      public static var developer:Boolean = false;

      private static var counted:Object = {};
      private static var on:Boolean = false;

      public static function init() : void
      {
         if(!ModSettings.flag("unlockAll",true))
         {
            Platform.log("unlocks: off (unlockAll false), the game's own ownership answers");
            return;
         }
         on = true;
         Hooks.itemOwned.add(ownsItem);
         Hooks.costumeOwned.add(ownsCostume);
         Hooks.colorSchemeOwned.add(ownsColor);
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet == null || packet.type != PERKS)
            {
               return false;
            }
            try
            {
               developer = packet.method_5885();
               Platform.log("unlocks: developer title " + (developer ? "allowed" : "not allowed") + " by the server");
            }
            catch(e:Error)
            {
            }
            return true;
         });
      }

      public static function colourCount(scheme:Object) : int
      {
         return on && ownsItem("UniversalColor",scheme) ? int(HeroType.var_12147.length) : 0;
      }

      private static function ownsItem(kind:String, item:Object) : Boolean
      {
         if(kind == "Stance")
         {
            return item != null;
         }
         if(kind == "UniversalColor" || kind == "RandomColor")
         {
            return item != null && class_76.var_1809.indexOf(item) >= 0 && allowed(kind,item.mColorSchemeName);
         }
         if(item == null || NAME_FIELDS[kind] == null || neverOwned(kind,item))
         {
            return false;
         }
         if(kind == "Moniker" && item[NAME_FIELDS[kind]] == DEVELOPER)
         {
            return developer;
         }
         return allowed(kind,item[NAME_FIELDS[kind]]);
      }

      private static function ownsCostume(costume:Object, hero:Object) : Boolean
      {
         if(costume == null || costume.var_7289 == null || hero != null && hero != costume.var_7289)
         {
            return false;
         }
         return allowed("Costume",costume.mCostumeName);
      }

      private static function ownsColor(costume:Object, scheme:Object) : Boolean
      {
         if(costume == null || scheme == null || class_76.var_1809.indexOf(scheme) < 0)
         {
            return false;
         }
         return allowed("UniversalColor",scheme.mColorSchemeName);
      }

      private static function neverOwned(kind:String, item:Object) : Boolean
      {
         switch(kind)
         {
            case "SpawnBot":
               return item == class_574.var_659;
            case "Avatar":
               return item == class_16.var_5274;
            case "PlayerTheme":
               return item == class_297.var_2923;
         }
         return false;
      }

      private static function allowed(kind:String, name:String) : Boolean
      {
         if(counted[kind] == null)
         {
            counted[kind] = true;
            Platform.log("unlocks: " + kind + " rows count as owned (everything is unlocked)");
         }
         return true;
      }
   }
}
