package bh.platform
{
   import bh.platform.net.P2PMatch;
   import bh.platform.net.PrivateServer;
   import flash.utils.getTimer;

   public final class RankedPreview
   {
      private static var shown:Object = null;
      private static var inQueueMatch:Boolean = false;
      private static var shownAt:int = 0;
      private static var holding:Boolean = false;
      private static const SHOW_MS:int = 6000;

      public static function init() : void
      {
         Hooks.matchPreviewShown.add(onShown);
         Hooks.frameStarting.add(onFrame);
         Hooks.gameStateChanging.add(onState);
      }

      private static function onState(from:uint, to:uint) : void
      {
         if(!inQueueMatch || to != 1 || from == 1)
         {
            return;
         }
         inQueueMatch = false;
         try
         {
            var core:Object = ScreenManager.owner;
            var p:NetPacket = new NetPacket(32);
            core.sendToServer(p);
            p.method_839();
            PrivateServer.log("queue match over: back to the own queue lobby (32)");
         }
         catch(e:Error)
         {
            ErrorLog.write("queue match: back to the lobby: " + e);
         }
      }

      private static function onShown(core:Object, info:Object) : void
      {
         var q:Object = P2PMatch.queueMatch;
         P2PMatch.queueMatch = null;
         if(q == null || info == null)
         {
            return;
         }
         inQueueMatch = true;
         try
         {
            var playlist:Object = class_301.var_11302[uint(q.playlist)];
            var screen:Object = playlist != null && playlist == class_301.PLAYLIST_RANKED1V1 ?
               ScreenManager.sScreenMatchPreviewRanked1v1 : (playlist != null && playlist == class_301.PLAYLIST_RANKED2V2 ?
               ScreenManager.sScreenMatchPreviewRanked2v2 : null);
            if(screen == null)
            {
               return;
            }
            core.var_4113.SetData(!q.known,uint(q.wins),uint(q.matches) - uint(q.wins));
            info.var_12621 = uint(q.playlist);
            if(uint(q.seriesGames) > 0)
            {
               info.var_5226 = true;
               for each(var sp:Object in info.var_9485)
               {
                  sp.var_6179 = uint(q.series[uint(sp.var_12098)] || 0);
               }
            }
            for each(var pl:Object in info.var_9485)
            {
               if(class_76.var_12696[pl.var_11388] == null || pl.var_2833 == null ||
                  CostumeType.var_12721[pl.var_2833.var_14823] == null)
               {
                  PrivateServer.log("queue match: player " + pl.var_12098 + " has no colour or skin the preview can show; " +
                     "the plain preview stays");
                  return;
               }
            }
            P2PMatch.uniqueColours(core);
            matchColours(core,info);
            screen.method_6837(info);
            ScreenManager.var_12737.Hide();
            var shownColours:Array = [];
            for each(var sc:Object in info.var_9485)
            {
               shownColours.push(sc.var_12098 + ":" + sc.var_11388);
            }
            PrivateServer.log("queue match: preview colours " + shownColours.join(" "));
            if(screen === ScreenManager.sScreenMatchPreviewRanked1v1)
            {
               var me:uint = uint(core.var_14656);
               var them:uint = 0;
               for each(var op:Object in info.var_9485)
               {
                  if(uint(op.var_12098) != me)
                  {
                     them = uint(op.var_12098);
                  }
               }
               RatingTags.preview([[screen.mPlayerPreview1.var_4483,me],[screen.mPlayerPreview2.var_4483,them]]);
               RatingExtras.series(q,me,them);
            }
            else
            {
               var mine:uint = uint(core.var_14656);
               var myTeam:Object = null;
               var order:Array = [];
               for each(var p2:Object in info.var_9485)
               {
                  if(uint(p2.var_12098) == mine)
                  {
                     myTeam = p2.team;
                     order.push(mine);
                  }
               }
               for each(var p3:Object in info.var_9485)
               {
                  if(uint(p3.var_12098) != mine && p3.team == myTeam)
                  {
                     order.push(uint(p3.var_12098));
                  }
               }
               for each(var p4:Object in info.var_9485)
               {
                  if(uint(p4.var_12098) != mine && p4.team != myTeam)
                  {
                     order.push(uint(p4.var_12098));
                  }
               }
               var previews:Array = [screen.mPlayerPreview1,screen.mPlayerPreview2,screen.mPlayerPreview3,screen.mPlayerPreview4];
               var tagged:Array = [];
               for(var oi:int = 0; oi < order.length && oi < 4; oi++)
               {
                  tagged.push([previews[oi].var_4483,order[oi]]);
               }
               RatingTags.preview(tagged);
            }
            shown = screen;
            shownAt = getTimer();
            holding = true;
            core.var_2677.method_2935();
            PrivateServer.log("queue match: the ranked preview (" + (q.known ? q.wins + " of " + q.matches + " won before" :
               "no history") + (uint(q.seriesGames) > 0 ? ", rematch series " + JSON.stringify(q.series) : "") + ")");
         }
         catch(e:Error)
         {
            ErrorLog.write("ranked preview: " + e + " " + e.getStackTrace());
         }
      }

      private static function matchColours(core:Object, info:Object) : void
      {
         var legends:Object = core.var_7050;
         for each(var row:Object in info.var_9485)
         {
            for(var i:int = 0; i < int(legends.length); i++)
            {
               var p:Object = legends[i];
               if(uint(p.var_14656) == uint(row.var_12098) && p.var_14421 != null &&
                  uint(p.var_14421.var_9518) != uint(row.var_11388))
               {
                  PrivateServer.log("queue match: player " + row.var_12098 + "'s preview colour " + row.var_11388 +
                     " -> " + p.var_14421.var_9518 + " (the match's)");
                  row.var_11388 = uint(p.var_14421.var_9518);
               }
            }
         }
      }

      private static function onFrame() : void
      {
         if(shown == null)
         {
            return;
         }
         try
         {
            var core:Object = ScreenManager.owner;
            if(holding && getTimer() - shownAt >= SHOW_MS)
            {
               holding = false;
               core.var_2677.method_2487();
            }
            if(core != null && !holding && uint(core.var_3500) == 0)
            {
               if(shown.isActive)
               {
                  shown.Hide();
               }
               shown = null;
               RatingTags.previewGone();
            }
         }
         catch(e:Error)
         {
            shown = null;
            RatingTags.previewGone();
         }
      }
   }
}
