package port.runtime.services;

class ServiceError #if openfl extends openfl.errors.Error #elseif heaps extends flash.errors.Error #end {
    #if !(openfl || heaps)
    public var errorID(default, null):Int;
    public var message(default, null):String;
    #end

    public function new(errorID:Int, message:String) {
        #if (openfl || heaps)
        super("Error #" + errorID + ": " + message, errorID);
        name = errorID == 2030 ? "EOFError" : errorID >= 3000 && errorID < 4000 ? "IOError" : "Error";
        #else
        this.errorID = errorID;
        this.message = "Error #" + errorID + ": " + message;
        #end
    }

    #if !(openfl || heaps)
    public function toString():String {
        return message;
    }
    #end
}
