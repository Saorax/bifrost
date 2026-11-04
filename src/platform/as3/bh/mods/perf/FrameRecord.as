package bh.mods.perf
{
   public final class FrameRecord
   {
      public var at:int;
      public var ms:int;
      public var pre:int;
      public var sim:int;
      public var draw:int;
      public var work:int;
      public var outside:int;
      public var steps:int;
      public var resim:int;
      public var tool:int;
      public var gc:Number = 0;
      public var mem:Number = 0;
      public var loads:String;

      public function FrameRecord()
      {
      }
   }
}
