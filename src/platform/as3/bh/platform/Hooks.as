package bh.platform
{
   public final class Hooks
   {
      public static const afterStartup:Hook = new Hook("afterStartup");

      public static const tablesRegistered:Hook = new Hook("tablesRegistered");

      public static const tableParsing:Hook = new Hook("tableParsing");

      public static const screenCreated:Hook = new Hook("screenCreated");

      public static const gameCreated:Hook = new Hook("gameCreated");

      public static const fileLoaded:Hook = new Hook("fileLoaded");

      public static const loadSetLoaded:Hook = new Hook("loadSetLoaded");

      public static const gameStateChanging:Hook = new Hook("gameStateChanging");

      public static const matchStarted:Hook = new Hook("matchStarted");

      public static const matchEnded:Hook = new Hook("matchEnded");

      public static const settingsAttached:Hook = new Hook("settingsAttached");

      public static const settingWritten:Hook = new Hook("settingWritten");

      public static const keyDown:Hook = new Hook("keyDown");

      public static const keyUp:Hook = new Hook("keyUp");

      public static const controllerAdded:Hook = new Hook("controllerAdded");

      public static const controllerRemoved:Hook = new Hook("controllerRemoved");

      public static const packetSending:Hook = new Hook("packetSending");

      public static const packetReceived:Hook = new Hook("packetReceived");

      public static const mainMenuButtonsBuilt:Hook = new Hook("mainMenuButtonsBuilt");

      public static const mainMenuLayout:Hook = new Hook("mainMenuLayout");

      public static const mainMenuInput:Hook = new Hook("mainMenuInput");

      public static const levelSelectInput:Hook = new Hook("levelSelectInput");

      public static const mainMenuFocusChanged:Hook = new Hook("mainMenuFocusChanged");

      public static const mainMenuHighlight:Hook = new Hook("mainMenuHighlight");

      public static const stringsLoaded:Hook = new Hook("stringsLoaded");

      public static const inputSampled:Hook = new Hook("inputSampled");

      public static const inputSampling:Hook = new Hook("inputSampling");

      public static const colorSchemeOwned:Hook = new Hook("colorSchemeOwned");

      public static const costumeOwned:Hook = new Hook("costumeOwned");

      public static const itemOwned:Hook = new Hook("itemOwned");

      public static const fileResolving:Hook = new Hook("fileResolving");

      public static const settingsScreenShown:Hook = new Hook("settingsScreenShown");

      public static const launchArgs:Hook = new Hook("launchArgs");

      public static const levelArtLoading:Hook = new Hook("levelArtLoading");

      public static const csvParsing:Hook = new Hook("csvParsing");

      public static const dataCheckFailed:Hook = new Hook("dataCheckFailed");

      public static const gameError:Hook = new Hook("gameError");

      public static const optionsMenuBuilding:Hook = new Hook("optionsMenuBuilding");

      public static const optionsMenuShown:Hook = new Hook("optionsMenuShown");

      public static const simulationFrame:Hook = new Hook("simulationFrame");

      public static const legendStepping:Hook = new Hook("legendStepping");

      public static const frameStarting:Hook = new Hook("frameStarting");

      public static const frameRendering:Hook = new Hook("frameRendering");

      public static const fileDeferring:Hook = new Hook("fileDeferring");

      public static const simulationRollback:Hook = new Hook("simulationRollback");

      public static const botMatchTime:Hook = new Hook("botMatchTime");

      public static const replayEndMatchTime:Hook = new Hook("replayEndMatchTime");

      public static const matchPreviewShown:Hook = new Hook("matchPreviewShown");

      public static const matchStartCollecting:Hook = new Hook("matchStartCollecting");

      public static const precacheCollecting:Hook = new Hook("precacheCollecting");

      public static const pauseMenuPausing:Hook = new Hook("pauseMenuPausing");

      public static const gfxResolving:Hook = new Hook("gfxResolving");

      public static const artPendingChecking:Hook = new Hook("artPendingChecking");

      public static const trainingMenuBuilt:Hook = new Hook("trainingMenuBuilt");

      public static const trainingRowState:Hook = new Hook("trainingRowState");

      public static const trainingRowValue:Hook = new Hook("trainingRowValue");

      public static const trainingRowChange:Hook = new Hook("trainingRowChange");

      public static const mainMenuTilePressed:Hook = new Hook("mainMenuTilePressed");

      public static const addFriendPressed:Hook = new Hook("addFriendPressed");

      public static const podiumAddFriendPressed:Hook = new Hook("podiumAddFriendPressed");

      public static const friendsMenuBuilt:Hook = new Hook("friendsMenuBuilt");

      public static const friendsTabInput:Hook = new Hook("friendsTabInput");

      public static const replaysInput:Hook = new Hook("replaysInput");

      public static const replaysRowsDrawing:Hook = new Hook("replaysRowsDrawing");

      public static const friendsTabRefreshed:Hook = new Hook("friendsTabRefreshed");

      public static const guildMemberMenuBuilt:Hook = new Hook("guildMemberMenuBuilt");

      public static const guildAddFriendPressed:Hook = new Hook("guildAddFriendPressed");

      public static const guildCreatePressed:Hook = new Hook("guildCreatePressed");

      public static const guildCreateShown:Hook = new Hook("guildCreateShown");

      public static const skirmishFactionRewards:Hook = new Hook("skirmishFactionRewards");

      public static const languageLoading:Hook = new Hook("languageLoading");

      public static const musicStopping:Hook = new Hook("musicStopping");

      public static const windowModeStepping:Hook = new Hook("windowModeStepping");

      public static const windowModeApplying:Hook = new Hook("windowModeApplying");

      public static const cameraPlaced:Hook = new Hook("cameraPlaced");

      public static const legendTinted:Hook = new Hook("legendTinted");

      public static const matchStatsRecording:Hook = new Hook("matchStatsRecording");

      public static const statsDumping:Hook = new Hook("statsDumping");

      public static const scoreboardInput:Hook = new Hook("scoreboardInput");

      public static const urlOpening:Hook = new Hook("urlOpening");

      public function Hooks()
      {
      }
   }
}
