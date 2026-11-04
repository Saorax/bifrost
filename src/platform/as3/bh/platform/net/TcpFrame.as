package bh.platform.net
{
   import flash.utils.ByteArray;

   public final class TcpFrame
   {
      public function TcpFrame()
      {
      }

      public static function encode(packet:NetPacket) : ByteArray
      {
         var out:ByteArray = new ByteArray();
         var type:uint = uint(packet.type);
         var first:Boolean = LinkUpdater.method_6298(packet);
         var second:Boolean = LinkUpdater.method_1357(packet);
         out.writeShort(first || second ? type | 0x8000 : type);
         if(first)
         {
            out.writeUnsignedInt(packet.var_960);
         }
         else if(second)
         {
            out.writeUnsignedInt(packet.var_924);
         }
         var payload:ByteArray = packet.var_5085.var_15327;
         out.writeShort(payload.length);
         out.writeBytes(payload);
         out.position = 0;
         return out;
      }

      public static function decode(bytes:ByteArray) : NetPacket
      {
         var start:uint = bytes.position;
         if(bytes.bytesAvailable < 2)
         {
            return null;
         }
         var type:uint = bytes.readUnsignedShort();
         var extra:uint = 0;
         if((type & 0x8000) != 0)
         {
            if(bytes.bytesAvailable < 4)
            {
               bytes.position = start;
               return null;
            }
            extra = bytes.readUnsignedInt();
         }
         if(bytes.bytesAvailable < 2)
         {
            bytes.position = start;
            return null;
         }
         var length:uint = bytes.readUnsignedShort();
         if(bytes.bytesAvailable < length)
         {
            bytes.position = start;
            return null;
         }
         var payload:ByteArray = new ByteArray();
         if(length != 0)
         {
            bytes.readBytes(payload,0,length);
         }
         var packet:NetPacket = new NetPacket(type & 0x7FFF,payload);
         packet.method_1608(extra);
         return packet;
      }
   }
}
