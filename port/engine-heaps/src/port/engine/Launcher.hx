package port.engine;

import haxe.io.Path;

class Launcher {
	public static final GAMES = ["dx11" => "game-dx11.hl", "dx12" => "game-dx12.hl", "vulkan" => "game-dx11.hl"];

	public static function plan(renderer:String, bin:String, exists:String->Bool):{folder:String, game:String,
		renderer:String, note:Null<String>} {
		var asked = GAMES.exists(renderer) ? renderer : "dx11";
		var folder = asked == "vulkan" ? Path.join([Path.directory(bin), "bin-vulkan"]) : bin;
		var game = Path.join([bin, GAMES.get(asked)]);
		var missing = !exists(game) ? game
			: asked == "vulkan" && !exists(Path.join([folder, "d3d11.dll"])) ? Path.join([folder, "d3d11.dll"])
			: null;
		if (missing != null && asked != "dx11")
			return {folder: bin, game: Path.join([bin, GAMES.get("dx11")]), renderer: "dx11",
				note: 'renderer $asked: $missing is missing, starting dx11'};
		return {folder: folder, game: game, renderer: asked, note: null};
	}

	static function main() {
		var bin = Path.directory(Path.normalize(sys.FileSystem.fullPath(Sys.programPath())));
		var storage = Sys.getEnv("BH_PORT_STORAGE_DIR");
		if (storage == null || storage == "") storage = Path.join([Path.directory(bin), "storage"]);
		var settings = EngineSettings.load(Path.join([storage, "engine.json"]));
		var run = plan(settings.renderer, bin, sys.FileSystem.exists);
		if (run.note != null) Sys.println("launcher: " + run.note);
		Sys.println('launcher: renderer ${run.renderer} (${run.game})');
		Sys.setCwd(run.folder);
		Sys.exit(Sys.command(Path.join([run.folder, "hl.exe"]), [run.game].concat(Sys.args())));
	}
}
