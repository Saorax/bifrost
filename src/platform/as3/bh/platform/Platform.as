package bh.platform
{
   import bh.platform.net.Net;
   import bh.platform.net.PrivateServer;
   import flash.desktop.NativeApplication;
   import flash.events.KeyboardEvent;
   import flash.filesystem.File;
   import flash.ui.Keyboard;

   public final class Platform
   {
      private static var started:Boolean = false;

      public function Platform()
      {
      }

      public static function init() : void
      {
         if(started)
         {
            return;
         }
         started = true;
         moveOldFiles();
         SessionLogs.rotate();
         ErrorLog.init();
         SaveCopy.run();
         CloudSave.applyPending();
         Branding.init();
         PrivateServer.init();
         Hooks.gameStateChanging.add(onGameStateChanging);
         Hooks.keyDown.add(function(e:Object):Boolean
         {
            if(e.keyCode == 27)
            {
               e.preventDefault();
            }
            return false;
         });
         Hooks.gameCreated.add(function(main:Object):void
         {
            try
            {
               var guard:Function = function(e:KeyboardEvent):void
               {
                  if(e.keyCode == Keyboard.ESCAPE)
                  {
                     e.preventDefault();
                  }
               };
               main.stage.addEventListener(KeyboardEvent.KEY_DOWN,guard,true,int.MAX_VALUE);
               main.stage.addEventListener(KeyboardEvent.KEY_DOWN,guard,false,int.MAX_VALUE);
            }
            catch(e:Error)
            {
               log("Esc guard not set: " + e);
            }
         });
         Hooks.artPendingChecking.add(nothingPending);
         BmodImport.init();
         MoveEditor.init();
         LegendStats.init();
         try
         {
            ContentMods.init();
         }
         catch(e:Error)
         {
            log("content mods failed: " + e.getStackTrace());
         }
         Unlocks.init();
         Moderation.init();
         TrainingModes.init();
         RankedPreview.init();
         Ranks.init();
         NoStore.init();
         MissionRewards.init();
         PassMatchStars.init();
         RatingTags.init();
         RatingExtras.init();
         LoadingBackground.init();
         MoveEditor.initLoaded();
         LegendStats.initLoaded();
         Net.init();
         LaunchOptions.init();
         FramePacing.init();
         Vsync.init();
         WindowModes.init();
         StatsOverlay.init();
         ProfilePicks.init();
         CloudSave.init();
         VersionLabel.init();
         InputDisplay.init();
         OnlineTraining.init();
         TrainingState.init();
         TrainingDummy.init();
         FrameData.init();
         HitboxTrail.init();
         DummyDrift.init();
         DummyRecovery.init();
         TrainingKeys.init();
         TrainingMenu.init();
         ScreenShake.init();
         ReducedFlashes.init();
         ClassicEffects.init();
         PostMatchStats.init();
         LeaderboardWindow.init();
         BackTrail.init();
         FrameRateWatch.init();
         PlayerCounts.init();
         Screenshot.init();
         ReplayExport.init();
         ReplayIndex.init();
         PhotoCamera.init();
         Setups.init();
         Controllers.init();
         ModList.registerAll();
      }

      private static function nothingPending() : Boolean
      {
         var map:Object = ArchiveLoader.var_13644;
         if(map == null)
         {
            return false;
         }
         for(var k:String in map.h)
         {
            return false;
         }
         if(map.rh != null)
         {
            for(k in map.rh)
            {
               return false;
            }
         }
         return true;
      }

      public static const MATCH_RUNNING:uint = 6;

      public static var toolTime:int = 0;

      public static var matchRunning:Boolean = false;

      private static function onGameStateChanging(from:uint, to:uint) : void
      {
         matchRunning = to == MATCH_RUNNING;
         if(to == MATCH_RUNNING && from != MATCH_RUNNING)
         {
            Hooks.matchStarted.fire();
         }
         else if(from == MATCH_RUNNING && to != MATCH_RUNNING)
         {
            Hooks.matchEnded.fire(to);
         }
      }

      public static const DATA_FOLDER:String = "Bifrost";

      public static const APP_ID:String = "BrawlhallaAir";

      private static var folderName:String = null;

      public static function dataFolder() : String
      {
         if(folderName == null)
         {
            folderName = DATA_FOLDER;
            try
            {
               var id:String = NativeApplication.nativeApplication.applicationID;
               if(id != null && id != APP_ID)
               {
                  folderName = DATA_FOLDER + "-" + (id.indexOf(APP_ID) == 0 && id.length > APP_ID.length ? id.substr(APP_ID.length) : id);
               }
            }
            catch(e:Error)
            {
            }
         }
         return folderName;
      }

      public static function dataFile(name:String) : File
      {
         return File.documentsDirectory.resolvePath(dataFolder() + "/" + name);
      }

      private static function moveOldFiles() : void
      {
         try
         {
            if(dataFolder() != DATA_FOLDER)
            {
               return;
            }
            var folder:File = File.documentsDirectory.resolvePath(DATA_FOLDER);
            folder.createDirectory();
            for each(var old:File in File.documentsDirectory.getDirectoryListing())
            {
               var name:String = old.name;
               if(name.indexOf("bh-") != 0 || (!old.isDirectory && !/\.(txt|json|log)$/i.test(name)))
               {
                  continue;
               }
               var target:File = folder.resolvePath(name);
               if(!target.exists)
               {
                  old.moveTo(target,false);
               }
            }
         }
         catch(e:Error)
         {
         }
      }

      public static function log(text:String) : void
      {
         trace("[bh-platform] " + text);
         if(++logged <= 100)
         {
            ErrorLog.write("platform: " + text);
         }
      }

      private static var logged:int = 0;
   }
}
