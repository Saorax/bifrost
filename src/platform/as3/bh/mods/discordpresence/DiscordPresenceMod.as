package bh.mods.discordpresence
{
   import bh.platform.Platform;
   import bh.platform.Hooks;
   import bh.platform.ModSettings;
   import bh.platform.Modal;
   import bh.platform.net.PrivateServer;
   import flash.desktop.NativeApplication;
   import flash.desktop.NativeProcess;
   import flash.desktop.NativeProcessStartupInfo;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.NativeProcessExitEvent;
   import flash.events.ProgressEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.SharedObject;
   import flash.utils.Timer;

   public final class DiscordPresenceMod
   {
      public static const CLIENT_ID:String = "828146347348721694";
      public static const BRIDGE:String = "BifrostDiscord.exe";
      public static const LAUNCHER:String = "Brawlhalla.exe";
      public static const MARKER:String = "bifrost-engine.json";
      public static const FILE:String = "bh-presence.json";
      private static var lastDiagnostic:String = null;
      private static var lastDiagnosticAt:Number = 0;
      public static const LOG:String = "bh-presence.txt";

      public static const PREF_ENABLED:String = "bhDiscordPresence";
      public static const PREF_JOIN:String = "bhDiscordJoin";

      public static const SPECTATE:int = 11006;
      public static const SECRET_PREFIX:String = "bifrost://10.11/";

      private static var loaded:Boolean = false;
      private static var enabled:Boolean = true;
      private static var allowJoin:Boolean = false;
      private static var bridge:NativeProcess;
      private static var bridgeOutput:String = "";
      private static var lastActivity:String = "";
      private static var lastHeartbeat:Number = 0;
      private static var matchStartedAt:Number = 0;
      private static var queueRequested:Boolean = false;
      private static var queueStartedAt:Number = 0;
      private static var joinable:Boolean = false;
      private static var pendingRoom:uint = 0;
      private static var pendingUntil:Number = 0;
      private static var pendingWarned:Boolean = false;
      private static var timer:Timer;

      public function DiscordPresenceMod()
      {
      }

      public static function register() : void
      {
         Hooks.settingsAttached.add(onSettingsAttached);
         onSettingsAttached(GameApp.savedGameData);
         Hooks.stringsLoaded.add(addStrings);
         Hooks.screenCreated.add(addSettings);
         Hooks.packetSending.add(onPacketSending);
         Hooks.matchStarted.add(function():void
         {
            matchStartedAt = now();
            queueRequested = false;
            refresh(true);
         });
         Hooks.matchEnded.add(function(to:uint):void
         {
            matchStartedAt = 0;
            refresh(true);
         });
         Hooks.gameCreated.add(function(main:Object):void
         {
            refresh(true);
         });
         NativeApplication.nativeApplication.addEventListener(Event.EXITING,function(e:Event):void
         {
            stopBridge();
         });
         timer = new Timer(2000);
         timer.addEventListener("timer",function(e:Event):void
         {
            refresh(false);
            tryPendingJoin();
         });
         timer.start();
      }

      private static function onSettingsAttached(value:SharedObject) : void
      {
         if(loaded || value == null || value !== GameApp.savedGameData)
         {
            return;
         }
         loaded = true;
         enabled = readPreference(PREF_ENABLED,true);
         allowJoin = readPreference(PREF_JOIN,false);
         refresh(true);
      }

      private static function readPreference(key:String, fallback:Boolean) : Boolean
      {
         var store:SharedObject = GameApp.savedGameData;
         if(store != null && store.data != null && store.data.hasOwnProperty(key))
         {
            fallback = Boolean(store.data[key]);
         }
         return ModSettings.flag(key,fallback);
      }

      private static function getPreference(key:String) : Boolean
      {
         return key == PREF_ENABLED ? enabled : allowJoin;
      }

      private static function setPreference(key:String, value:Boolean) : void
      {
         if(key == PREF_ENABLED)
         {
            enabled = value;
         }
         else if(key == PREF_JOIN)
         {
            allowJoin = value;
         }
         ModSettings.setFlag(key,value);
         refresh(true);
      }

      private static function addStrings(language:Localization) : void
      {
         var strings:Object = language.var_15061;
         strings.method_65("UI_Bifrost_DiscordPresence","Discord Rich Presence");
         strings.method_65("UI_Bifrost_DiscordPresence_Tooltip","Show your current Bifrost activity in Discord.");
         strings.method_65("UI_Bifrost_DiscordJoin","Allow Discord Joining");
         strings.method_65("UI_Bifrost_DiscordJoin_Tooltip","Let Discord friends spectate your open Custom lobby. Off by default.");
      }

      private static function addSettings(screen:Object) : void
      {
         if(!(screen is class_540))
         {
            return;
         }
         var list:Object = screen.var_4818;
         addSetting(screen,list,"UI_Bifrost_DiscordPresence",PREF_ENABLED);
         addSetting(screen,list,"UI_Bifrost_DiscordJoin",PREF_JOIN);
         list.method_5337();
      }

      private static function addSetting(screen:Object, list:Object, label:String, key:String) : void
      {
         list.method_7864(label,function(e:MouseEvent,index:uint,change:int):void
         {
            setPreference(key,!getPreference(key));
         },function(e:MouseEvent,index:uint):void
         {
            screen.method_6916(e,index);
         },function(index:uint):void
         {
            list.method_786(index,getPreference(key) ? "UI_On" : "UI_Off");
         },"a_SocialHubBtnArrows");
      }

      private static function onPacketSending(connection:Object, packet:Object) : Boolean
      {
         if(packet != null)
         {
            if(packet.type == 31)
            {
               queueRequested = true;
            }
            else if(packet.type == 32 || packet.type == 55 || packet.type == 79 || packet.type == 81)
            {
               queueRequested = false;
            }
         }
         return false;
      }

      private static function refresh(force:Boolean) : void
      {
         var activity:Object = enabled ? buildActivity() : null;
         var json:String = activity != null ? JSON.stringify(activity) : "null";
         joinable = activity != null && activity.secrets != null;
         writeDiagnostic(activity,(enabled ? "1" : "0") + json);
         if(activity == null && (bridge == null || !bridge.running))
         {
            return;
         }
         if(!ensureBridge())
         {
            return;
         }
         var stamp:Number = now();
         if(force || json != lastActivity || stamp - lastHeartbeat >= 15)
         {
            try
            {
               bridge.standardInput.writeUTFBytes(json + "\n");
               lastActivity = json;
               lastHeartbeat = stamp;
            }
            catch(e:Error)
            {
               log("Discord bridge write failed: " + e.message);
               stopBridge(false);
            }
         }
      }

      private static function buildActivity() : Object
      {
         var activity:Object = {"details":"In the menus","instance":false};
         if(GameApp.mainInstance == null)
         {
            return activity;
         }
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var lobby:Object = core != null ? core.var_6244 : null;
            if(core == null || lobby == null)
            {
               return activity;
            }
            var inMatch:Boolean = uint(core.gameState) == 6;
            var spectating:Boolean = uint(lobby.var_486) == 1 || (inMatch && (uint(core.var_3595) & (262144 | 524288)) != 0);
            var inLobby:Boolean = lobby.method_5131() != null || spectating || inMatch;
            if(!inLobby)
            {
               return activity;
            }

            var lobbyName:String = modeName(core,lobby);
            var teams:Array = participantNames(core,lobby,true);
            var opponents:Array = participantNames(core,lobby,false);
            var withText:String = teams.length > 0 ? " with " + teams.join(", ") : "";
            var searching:Boolean = Boolean(lobby.var_14129) || Boolean(lobby.var_5638) || queueRequested;
            if(spectating)
            {
               activity.details = inMatch ? "Spectating a match · " + lobbyName : "Spectating · " + lobbyName;
            }
            else if(searching)
            {
               activity.details = "In queue · " + lobbyName + withText;
            }
            else if(inMatch)
            {
               activity.details = "Playing " + lobbyName + withText;
            }
            else
            {
               activity.details = "In lobby · " + lobbyName + withText;
            }
            activity.details = shorten(String(activity.details));

            var mode:uint = uint(lobby.var_9946);
            if(mode != 4 && mode != 32 && opponents.length > 0 && !searching)
            {
               activity.state = shorten("Versus " + opponents.join(", "));
            }

            if(searching)
            {
               if(queueStartedAt == 0)
               {
                  queueStartedAt = now();
               }
               activity.timestamps = {"start":queueStartedAt};
            }
            else
            {
               queueStartedAt = 0;
            }
            if(inMatch && !searching)
            {
               if(matchStartedAt == 0)
               {
                  matchStartedAt = now();
               }
               activity.timestamps = {"start":matchStartedAt};
            }
            else if(!inMatch)
            {
               matchStartedAt = 0;
            }

            var map:Object = searching ? null : currentMap(core,lobby,inMatch);
            var legend:String = currentLegend(core,lobby,inMatch,searching);
            var assets:Object = {};
            if(map != null)
            {
               assets.large_image = artKey("map",uint(map.var_8543),mapUrl(map));
               assets.large_text = shorten(String(map.mDisplayName || "Unknown Map") + " · Level " + uint(map.var_8543));
            }
            if(legend != "")
            {
               var hero:Object = currentHero(core,lobby,inMatch,searching);
               assets.small_image = hero != null ? artKey("legend",uint(hero.var_12172),legendUrl(hero)) :
                  "legend_placeholder";
               assets.small_text = shorten(legend);
            }
            activity.assets = assets;

            var room:uint = uint(lobby.var_13482);
            if(mode == 4 && room != 0)
            {
               var players:uint = Math.max(1,activePlayers(lobby));
               var most:uint = Math.max(players,uint(lobby.var_8309));
               activity.party = {"id":"bifrost-" + class_51.var_1352 + "-" + room,"size":[players,players >= most ?
                  players + 1 : most]};
               if(allowJoin && !inMatch && !spectating && PrivateServer.host != null && String(lobby.method_7083()) != "*****")
               {
                  activity.secrets = {"join":SECRET_PREFIX + room};
                  activity.instance = true;
               }
            }
         }
         catch(e:Error)
         {
            log("presence snapshot failed: " + e.message);
         }
         return activity;
      }

      private static function modeName(core:Object, lobby:Object) : String
      {
         if(lobby.var_2390 != null)
         {
            return class_256.method_1351(String(lobby.var_2390.mDisplayNameKey));
         }
         switch(uint(lobby.var_9946))
         {
            case 2:
               return "Couch Party";
            case 4:
               return "Custom Lobby";
            case 16:
               return "Tournament";
            case 32:
               return "Training";
            case 64:
               return "Arcade";
         }
         return "Online Lobby";
      }

      private static function participantNames(core:Object, lobby:Object, teammates:Boolean) : Array
      {
         var result:Array = [];
         try
         {
            var local:Object = lobby.method_5131();
            if(local == null)
            {
               return result;
            }
            var teamGame:Boolean = (uint(core.var_8999.var_2458) & 1) != 0;
            for each(var member:Object in lobby.var_1751)
            {
               if(member == null || member === local || uint(member.var_12512) == 1 || uint(member.var_12512) == 0)
               {
                  continue;
               }
               var sameTeam:Boolean = teamGame && uint(local.var_3540) != 0 && uint(member.var_3540) == uint(local.var_3540);
               if(sameTeam == teammates)
               {
                  var name:String = String(member.var_6307.var_14792 || "Player");
                  if(result.indexOf(name) < 0)
                  {
                     result.push(name);
                  }
               }
            }
         }
         catch(e:Error)
         {
         }
         return result;
      }

      private static function currentLegend(core:Object, lobby:Object, inMatch:Boolean, searching:Boolean) : String
      {
         try
         {
            if(inMatch && !searching && core.var_9499 != null && core.var_9499.var_13881 != null)
            {
               return String(core.var_9499.var_13881.mDisplayName);
            }
            var member:Object = lobby.method_5131();
            if(member == null)
            {
               return "";
            }
            if(uint(member.var_6607) == 0 && !searching)
            {
               return "";
            }
            if(member.var_13625 != null && Boolean(member.var_13625.var_12905))
            {
               return "Random";
            }
            var hero:Object = member.method_4742();
            return hero != null ? String(hero.mDisplayName) : "";
         }
         catch(e:Error)
         {
         }
         return "";
      }

      private static function currentHero(core:Object, lobby:Object, inMatch:Boolean, searching:Boolean) : Object
      {
         try
         {
            if(inMatch && !searching && core.var_9499 != null && core.var_9499.var_13881 != null)
            {
               return core.var_9499.var_13881;
            }
            var member:Object = lobby.method_5131();
            if(member == null || member.var_13625 != null && Boolean(member.var_13625.var_12905))
            {
               return null;
            }
            return member.method_4742();
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static const ART_KEYS:Object = {
         "legend_10":true,"legend_11":true,"legend_12":true,"legend_13":true,"legend_14":true,"legend_15":true,
         "legend_16":true,"legend_17":true,"legend_18":true,"legend_19":true,"legend_20":true,"legend_21":true,
         "legend_22":true,"legend_23":true,"legend_24":true,"legend_25":true,"legend_26":true,"legend_27":true,
         "legend_28":true,"legend_29":true,"legend_3":true,"legend_30":true,"legend_31":true,"legend_32":true,
         "legend_33":true,"legend_34":true,"legend_35":true,"legend_36":true,"legend_37":true,"legend_38":true,
         "legend_39":true,"legend_4":true,"legend_40":true,"legend_41":true,"legend_42":true,"legend_43":true,
         "legend_44":true,"legend_45":true,"legend_46":true,"legend_47":true,"legend_48":true,"legend_49":true,
         "legend_5":true,"legend_50":true,"legend_51":true,"legend_52":true,"legend_53":true,"legend_54":true,
         "legend_55":true,"legend_56":true,"legend_57":true,"legend_58":true,"legend_59":true,"legend_6":true,
         "legend_60":true,"legend_61":true,"legend_62":true,"legend_63":true,"legend_64":true,"legend_65":true,
         "legend_66":true,"legend_67":true,"legend_68":true,"legend_69":true,"legend_7":true,"legend_70":true,
         "legend_71":true,"legend_72":true,"legend_8":true,"legend_9":true,"map_1":true,"map_10":true,"map_100":true,
         "map_105":true,"map_11":true,"map_112":true,"map_115":true,"map_12":true,"map_123":true,"map_124":true,
         "map_127":true,"map_128":true,"map_129":true,"map_130":true,"map_131":true,"map_132":true,"map_135":true,
         "map_136":true,"map_137":true,"map_138":true,"map_139":true,"map_140":true,"map_141":true,"map_143":true,
         "map_144":true,"map_146":true,"map_15":true,"map_150":true,"map_151":true,"map_152":true,"map_153":true,
         "map_154":true,"map_16":true,"map_17":true,"map_174":true,"map_175":true,"map_177":true,"map_178":true,
         "map_18":true,"map_180":true,"map_184":true,"map_185":true,"map_186":true,"map_187":true,"map_188":true,
         "map_19":true,"map_190":true,"map_191":true,"map_2":true,"map_20":true,"map_210":true,"map_211":true,
         "map_212":true,"map_216":true,"map_217":true,"map_22":true,"map_220":true,"map_221":true,"map_222":true,
         "map_223":true,"map_226":true,"map_227":true,"map_229":true,"map_231":true,"map_232":true,"map_233":true,
         "map_234":true,"map_235":true,"map_236":true,"map_237":true,"map_238":true,"map_24":true,"map_242":true,
         "map_246":true,"map_249":true,"map_25":true,"map_250":true,"map_251":true,"map_252":true,"map_253":true,
         "map_254":true,"map_255":true,"map_258":true,"map_26":true,"map_266":true,"map_269":true,"map_271":true,
         "map_28":true,"map_29":true,"map_3":true,"map_31":true,"map_33":true,"map_35":true,"map_39":true,
         "map_40":true,"map_42":true,"map_43":true,"map_46":true,"map_47":true,"map_55":true,"map_56":true,
         "map_57":true,"map_58":true,"map_59":true,"map_6":true,"map_62":true,"map_63":true,"map_64":true,
         "map_65":true,"map_7":true,"map_70":true,"map_73":true,"map_74":true,"map_75":true,"map_76":true,
         "map_8":true,"map_81":true,"map_84":true,"map_89":true,"map_90":true,"map_91":true,"map_94":true,
         "map_95":true,"map_99":true
      };

      public static const ART_URL:String = "https://api.saorax.com/game/";

      private static var mapUrls:Object = {};

      private static function artKey(kind:String, id:uint, fallback:String) : String
      {
         var key:String = kind + "_" + id;
         return ART_KEYS[key] == true ? key : fallback;
      }

      private static function mapUrl(map:Object) : String
      {
         var id:String = String(uint(map.var_8543));
         if(mapUrls[id] == null)
         {
            var url:String = "map_placeholder";
            try
            {
               var desc:Object = class_250.method_3445(LevelType(map));
               var it:* = desc != null ? desc.method_5430() : null;
               while(it != null && it.hasNext())
               {
                  var el:Object = it.next();
                  if(el.var_4402 == "Background" && el.exists("AssetName"))
                  {
                     url = ART_URL + "maps/asset?dir=Backgrounds&name=" + encodeURIComponent(String(el.method_4935("AssetName")));
                     break;
                  }
               }
            }
            catch(e:Error)
            {
            }
            mapUrls[id] = url;
         }
         return String(mapUrls[id]);
      }

      private static function legendUrl(hero:Object) : String
      {
         var portrait:String = hero.var_12260 != null ? String(hero.var_12260) : "";
         if(portrait == "")
         {
            return "legend_placeholder";
         }
         var swf:String = hero.var_6330 != null && String(hero.var_6330) != "" ? String(hero.var_6330) : "UI_Icons";
         return ART_URL + "getGfx/" + encodeURIComponent(swf.replace(/\.swf$/i,"")) + "/" + encodeURIComponent(portrait + "M") +
            "?format=png";
      }

      private static function currentMap(core:Object, lobby:Object, inMatch:Boolean) : Object
      {
         try
         {
            if(inMatch && core.var_14641 != null && core.var_14641.var_256 != null)
            {
               return core.var_14641.var_256;
            }
            return lobby.var_14860;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function activePlayers(lobby:Object) : uint
      {
         var count:uint = 0;
         try
         {
            for each(var member:Object in lobby.var_1751)
            {
               if(member != null && uint(member.var_12512) != 0 && uint(member.var_12512) != 1)
               {
                  count++;
               }
            }
         }
         catch(e:Error)
         {
         }
         return count;
      }

      private static function ensureBridge() : Boolean
      {
         if(bridge != null && bridge.running)
         {
            return true;
         }
         if(!NativeProcess.isSupported)
         {
            return false;
         }
         try
         {
            var executable:File = File.applicationDirectory.resolvePath(BRIDGE);
            var args:Vector.<String> = Vector.<String>([CLIENT_ID]);
            if(!executable.exists && builtInBridge())
            {
               executable = File.applicationDirectory.resolvePath(LAUNCHER);
               args = Vector.<String>(["--discord-bridge",CLIENT_ID]);
            }
            if(!executable.exists)
            {
               log(BRIDGE + " is missing next to BrawlhallaAir.swf");
               return false;
            }
            var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
            info.executable = executable;
            info.arguments = args;
            bridge = new NativeProcess();
            bridge.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA,onBridgeOutput);
            bridge.addEventListener(ProgressEvent.STANDARD_ERROR_DATA,onBridgeError);
            bridge.addEventListener(NativeProcessExitEvent.EXIT,onBridgeExit);
            bridge.start(info);
            lastActivity = "";
            log("started " + BRIDGE);
            return true;
         }
         catch(e:Error)
         {
            log("could not start " + BRIDGE + ": " + e.message);
         }
         return false;
      }

      private static function builtInBridge() : Boolean
      {
         try
         {
            var marker:File = File.applicationDirectory.resolvePath(MARKER);
            if(!marker.exists || !File.applicationDirectory.resolvePath(LAUNCHER).exists)
            {
               return false;
            }
            var stream:FileStream = new FileStream();
            stream.open(marker,FileMode.READ);
            var text:String = stream.readUTFBytes(stream.bytesAvailable);
            stream.close();
            var built:Boolean = Boolean(JSON.parse(text).discord_bridge);
            if(!built)
            {
               log(MARKER + " has no \"discord_bridge\": true; using " + BRIDGE);
            }
            return built;
         }
         catch(e:Error)
         {
            log("could not read " + MARKER + ": " + e.message);
         }
         return false;
      }

      private static function onBridgeOutput(e:ProgressEvent) : void
      {
         try
         {
            bridgeOutput += bridge.standardOutput.readUTFBytes(bridge.standardOutput.bytesAvailable);
            var end:int;
            while((end = bridgeOutput.indexOf("\n")) >= 0)
            {
               var line:String = bridgeOutput.substr(0,end).replace(/\r/g,"");
               bridgeOutput = bridgeOutput.substr(end + 1);
               if(line == "ready")
               {
                  log("Discord bridge: connected to Discord (Join and Ask to Join are listened for)");
               }
               else if(line.indexOf("join\t") == 0)
               {
                  log("Discord bridge: Join clicked");
                  acceptJoin(line.substr(5));
               }
               else if(line.indexOf("request\t") == 0)
               {
                  answerRequest(line.substr(8).split("\t"));
               }
            }
         }
         catch(error:Error)
         {
         }
      }

      private static function onBridgeError(e:ProgressEvent) : void
      {
         try
         {
            var text:String = bridge.standardError.readUTFBytes(bridge.standardError.bytesAvailable);
            if(text)
            {
               log("Discord bridge: " + text.replace(/[\r\n]+$/g,""));
            }
         }
         catch(error:Error)
         {
         }
      }

      private static function onBridgeExit(e:NativeProcessExitEvent) : void
      {
         bridge = null;
         bridgeOutput = "";
         lastActivity = "";
      }

      private static function answerRequest(fields:Array) : void
      {
         var user:String = String(fields[0]);
         if(!enabled || !allowJoin || !joinable || !/^\d+$/.test(user) || bridge == null || !bridge.running)
         {
            log("left a Discord join request from " + fields[1] + " unanswered (joining is off or the lobby isn't open)");
            return;
         }
         try
         {
            bridge.standardInput.writeUTFBytes("accept\t" + user + "\n");
            log("let " + fields[1] + " in from Discord");
         }
         catch(e:Error)
         {
            log("could not answer a Discord join request: " + e.message);
         }
      }

      private static function acceptJoin(secret:String) : void
      {
         if(secret.indexOf(SECRET_PREFIX) != 0)
         {
            log("ignored a Discord join for another version: " + secret);
            return;
         }
         var room:uint = uint(parseInt(secret.substr(SECRET_PREFIX.length)));
         if(room == 0)
         {
            return;
         }
         pendingRoom = room;
         pendingUntil = now() + 120;
         pendingWarned = false;
         log("Discord join for room " + room);
         tryPendingJoin();
      }

      private static function tryPendingJoin() : void
      {
         if(pendingRoom == 0)
         {
            return;
         }
         if(now() > pendingUntil)
         {
            log("gave up the Discord join for room " + pendingRoom + ": the game was never free to spectate it");
            pendingRoom = 0;
            return;
         }
         try
         {
            var core:Object = GameApp.mainInstance != null ? Object(GameApp.mainInstance).var_13259 : null;
            if(core == null || core.var_6244 == null || PrivateServer.host == null || core.serverConnection == null ||
               !core.serverConnection.isConnected())
            {
               return;
            }
            if(uint(core.gameState) != 0 || uint(core.var_6244.var_486) != 0)
            {
               if(!pendingWarned)
               {
                  pendingWarned = true;
                  Modal.show("Discord","Leave your lobby or match to join your friend's room " + pendingRoom + ".");
               }
               return;
            }
            var room:uint = pendingRoom;
            pendingRoom = 0;
            var packet:NetPacket = new NetPacket(SPECTATE);
            packet.writeUint(room);
            packet.method_5184(true);
            core.sendToServer(packet);
            packet.method_839();
            log("joining room " + room + " from Discord (sent 11006: play if there is room, else spectate)");
         }
         catch(e:Error)
         {
            pendingRoom = 0;
            log("Discord join failed: " + e.message);
         }
      }

      private static function stopBridge(clear:Boolean = true) : void
      {
         if(bridge != null)
         {
            var process:NativeProcess = bridge;
            bridge = null;
            try
            {
               if(process.running)
               {
                  if(clear)
                  {
                     process.standardInput.writeUTFBytes("null\n");
                  }
                  process.standardInput.writeUTFBytes("__quit__\n");
                  process.closeInput();
                  process.exit(true);
               }
            }
            catch(e:Error)
            {
               try
               {
                  if(process.running)
                  {
                     process.exit(true);
                  }
               }
               catch(ignored:Error)
               {
               }
            }
         }
         bridgeOutput = "";
         lastActivity = "";
      }

      private static function writeDiagnostic(activity:Object, key:String) : void
      {
         var stamp:Number = now();
         if(key == lastDiagnostic && stamp - lastDiagnosticAt < 20)
         {
            return;
         }
         lastDiagnostic = key;
         lastDiagnosticAt = stamp;
         try
         {
            var value:Object = {"game":"Brawlhalla (Bifrost)","enabled":enabled,"updated":now(),"activity":activity};
            if(activity != null)
            {
               value.details = activity.details;
               value.state = activity.state;
               value.start = activity.timestamps != null ? activity.timestamps.start : 0;
            }
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(FILE),FileMode.WRITE);
            stream.writeUTFBytes(JSON.stringify(value));
            stream.close();
         }
         catch(e:Error)
         {
         }
      }

      private static function log(line:String) : void
      {
         try
         {
            var stream:FileStream = new FileStream();
            stream.open(Platform.dataFile(LOG),FileMode.APPEND);
            stream.writeUTFBytes(new Date().toLocaleTimeString() + " " + line + "\r\n");
            stream.close();
         }
         catch(e:Error)
         {
         }
      }

      private static function shorten(value:String) : String
      {
         return value.length > 128 ? value.substr(0,125) + "..." : value;
      }

      private static function now() : Number
      {
         return Math.floor(new Date().time / 1000);
      }
   }
}
