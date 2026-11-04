package flash.errors;

class ReferenceError extends openfl.errors.Error {
    public function new(message:String = "", id:Int = 0) {
        super(message, id);
        name = "ReferenceError";
    }
}
