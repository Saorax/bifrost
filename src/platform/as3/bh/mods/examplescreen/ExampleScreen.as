package bh.mods.examplescreen
{
   import flash.display.MovieClip;

   public class ExampleScreen extends ScreenBase
   {
      public function ExampleScreen(game:GameCore)
      {
         super(game,"a_ScreenPopUpLegal","am_PanelInternal","UI_InformationTiles");
         var_3798 = "FadeIn";
         var_14711 = "FadeOut";
         var_7938 = false;
         var_5327 = true;
      }

      override public function OnCreateScreen() : void
      {
         addLocalizedText(panelClip,"am_Header",ExampleScreenMod.KEY_HEADER,Localization.var_13893);
         method_545();
         var container:MovieClip = class_51.method_3081(panelClip,"am_Container");
         method_6382(panelClip,false,true);
         var y:Number = -160;
         for each(var key:String in ExampleScreenMod.KEYS_BODY)
         {
            var line:MovieClip = class_687.method_1714("a_LegalText","UI_InformationTiles");
            var text:LocalizedText = addLocalizedText(line,"am_Text",key,Localization.FONT_15_SLIM);
            line.x = -326;
            line.y = y;
            y += 10 + text.method_4205();
            container.addChild(line);
         }
         var_12421 = 1;
         var_7257 = 0;
      }

      override public function HandleInput(param1:int) : Boolean
      {
         if(!method_5588())
         {
            return false;
         }
         switch(param1)
         {
            case 11:
            case 17:
            case 18:
            case 19:
            case 23:
               Hide();
               return true;
            default:
               return true;
         }
      }
   }
}
