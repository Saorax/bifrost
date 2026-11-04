window.MAP_SCHEMA = {
 "maps": 120,
 "elements": {
  "NavNode": {
   "count": 5170,
   "attributes": [
    [
     "NavID",
     5170
    ],
    [
     "Path",
     5170
    ],
    [
     "X",
     5162
    ],
    [
     "Y",
     5162
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc",
    "DynamicNavNode"
   ],
   "text": false,
   "example": {
    "NavID": "2",
    "Path": "5",
    "X": "110",
    "Y": "1810"
   }
  },
  "HardCollision": {
   "count": 1747,
   "attributes": [
    [
     "X1",
     1195
    ],
    [
     "X2",
     1195
    ],
    [
     "Y1",
     1065
    ],
    [
     "Y2",
     1065
    ],
    [
     "Y",
     682
    ],
    [
     "X",
     552
    ],
    [
     "Team",
     128
    ],
    [
     "NormalY",
     126
    ],
    [
     "NormalX",
     110
    ],
    [
     "AnchorX",
     8
    ],
    [
     "AnchorY",
     8
    ],
    [
     "Flag",
     4
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc",
    "DynamicCollision"
   ],
   "text": false,
   "example": {
    "X1": "0",
    "X2": "1000",
    "Y": "1850",
    "X": "0",
    "Y1": "1850",
    "Y2": "1850",
    "NormalX": "-1",
    "NormalY": "-1",
    "Team": "3",
    "AnchorX": "2476.95",
    "AnchorY": "487.4",
    "Flag": "sand"
   }
  },
  "KeyFrame": {
   "count": 1409,
   "attributes": [
    [
     "FrameNum",
     1409
    ],
    [
     "Y",
     701
    ],
    [
     "X",
     643
    ],
    [
     "Rotation",
     10
    ],
    [
     "CenterX",
     4
    ],
    [
     "CenterY",
     2
    ]
   ],
   "children": [],
   "parents": [
    "Animation",
    "Phase"
   ],
   "text": false,
   "example": {
    "FrameNum": "1",
    "Y": "-570",
    "X": "0",
    "CenterY": "350",
    "CenterX": "340",
    "Rotation": "0"
   }
  },
  "Platform": {
   "count": 1375,
   "attributes": [
    [
     "InstanceName",
     1375
    ],
    [
     "X",
     1195
    ],
    [
     "Y",
     1182
    ],
    [
     "Scale",
     396
    ],
    [
     "ScaleX",
     265
    ],
    [
     "AssetName",
     216
    ],
    [
     "H",
     216
    ],
    [
     "W",
     216
    ],
    [
     "Theme",
     196
    ],
    [
     "ScaleY",
     173
    ],
    [
     "ScoringType",
     112
    ],
    [
     "Rotation",
     67
    ],
    [
     "PlatformAssetSwap",
     17
    ]
   ],
   "children": [
    "Asset",
    "Platform"
   ],
   "parents": [
    "LevelDesc",
    "Platform",
    "MovingPlatform"
   ],
   "text": false,
   "example": {
    "InstanceName": "TopLeft",
    "Scale": "1.469",
    "X": "242.6",
    "Y": "-241.1",
    "ScaleY": "1.23",
    "H": "309.76",
    "W": "138.25",
    "ScaleX": "-1",
    "Theme": "Christmas",
    "Rotation": "180",
    "ScoringType": "SNOWBALL",
    "PlatformAssetSwap": "animated"
   }
  },
  "Asset": {
   "count": 1181,
   "attributes": [
    [
     "AssetName",
     1181
    ],
    [
     "H",
     1181
    ],
    [
     "W",
     1181
    ],
    [
     "X",
     480
    ],
    [
     "Y",
     460
    ],
    [
     "Rotation",
     150
    ],
    [
     "InstanceName",
     1
    ]
   ],
   "children": [],
   "parents": [
    "Platform"
   ],
   "text": false,
   "example": {
    "Rotation": "0",
    "H": "238.05",
    "W": "-413.82",
    "X": "0",
    "Y": "0"
   }
  },
  "AnimatedBackground": {
   "count": 1087,
   "attributes": [
    [
     "Midground",
     85
    ]
   ],
   "children": [
    "Gfx",
    "Scale",
    "Position",
    "Skew",
    "FrameOffset",
    "Rotation",
    "ForceDraw",
    "Loops",
    "SoundString",
    "SoundFrame"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "Midground": "true"
   }
  },
  "Gfx": {
   "count": 1087,
   "attributes": [],
   "children": [
    "AnimFile",
    "AnimClass"
   ],
   "parents": [
    "AnimatedBackground"
   ],
   "text": false,
   "example": {}
  },
  "AnimFile": {
   "count": 1087,
   "attributes": [],
   "children": [],
   "parents": [
    "Gfx"
   ],
   "text": true,
   "example": {}
  },
  "AnimClass": {
   "count": 1087,
   "attributes": [],
   "children": [],
   "parents": [
    "Gfx"
   ],
   "text": true,
   "example": {}
  },
  "Scale": {
   "count": 1081,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "Position": {
   "count": 1080,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "Respawn": {
   "count": 963,
   "attributes": [
    [
     "X",
     963
    ],
    [
     "Y",
     963
    ],
    [
     "Initial",
     377
    ],
    [
     "ExpandedInit",
     326
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc",
    "DynamicRespawn"
   ],
   "text": false,
   "example": {
    "X": "0",
    "Y": "1420",
    "Initial": "true",
    "ExpandedInit": "true"
   }
  },
  "Skew": {
   "count": 883,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "Point": {
   "count": 808,
   "attributes": [
    [
     "X",
     808
    ],
    [
     "Y",
     808
    ]
   ],
   "children": [],
   "parents": [
    "CustomPath"
   ],
   "text": false,
   "example": {
    "X": "2417",
    "Y": "1670"
   }
  },
  "ItemSpawn": {
   "count": 708,
   "attributes": [
    [
     "X",
     708
    ],
    [
     "Y",
     708
    ],
    [
     "W",
     708
    ],
    [
     "H",
     394
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc",
    "DynamicItemSpawn"
   ],
   "text": false,
   "example": {
    "X": "370",
    "Y": "-250",
    "W": "200",
    "H": "40"
   }
  },
  "Group": {
   "count": 608,
   "attributes": [
    [
     "Delay",
     600
    ],
    [
     "Count",
     533
    ],
    [
     "Dir",
     524
    ],
    [
     "Stagger",
     495
    ],
    [
     "Path",
     483
    ],
    [
     "Behavior",
     440
    ],
    [
     "Shared",
     178
    ],
    [
     "Count3",
     99
    ],
    [
     "Count4",
     91
    ],
    [
     "Delay3",
     52
    ],
    [
     "Stagger3",
     50
    ],
    [
     "Stagger4",
     48
    ],
    [
     "Delay4",
     32
    ],
    [
     "SharedPath",
     27
    ],
    [
     "DIR",
     1
    ]
   ],
   "children": [],
   "parents": [
    "WaveData"
   ],
   "text": false,
   "example": {
    "Count": "7",
    "Delay": "0",
    "Stagger": "100",
    "Stagger3": "300",
    "Dir": "CUSTOM",
    "Path": "CLOSE",
    "Count3": "3",
    "Count4": "3",
    "Delay3": "0",
    "Delay4": "0",
    "SharedPath": "TRUE",
    "Shared": "TRUE",
    "DIR": "SIDE",
    "Behavior": "FAST",
    "Stagger4": "0"
   }
  },
  "FrameOffset": {
   "count": 506,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "SoftCollision": {
   "count": 263,
   "attributes": [
    [
     "X1",
     263
    ],
    [
     "X2",
     263
    ],
    [
     "Y",
     236
    ],
    [
     "Y1",
     27
    ],
    [
     "Y2",
     27
    ],
    [
     "Team",
     19
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc",
    "DynamicCollision"
   ],
   "text": false,
   "example": {
    "X1": "0",
    "X2": "720",
    "Y": "0",
    "Y1": "0",
    "Y2": "0",
    "Team": "2"
   }
  },
  "NoSlideCollision": {
   "count": 235,
   "attributes": [
    [
     "Y1",
     173
    ],
    [
     "Y2",
     173
    ],
    [
     "X",
     132
    ],
    [
     "X1",
     103
    ],
    [
     "X2",
     103
    ],
    [
     "Y",
     62
    ],
    [
     "NormalX",
     51
    ],
    [
     "NormalY",
     50
    ],
    [
     "Team",
     12
    ]
   ],
   "children": [],
   "parents": [
    "DynamicCollision",
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "0",
    "Y1": "2220",
    "Y2": "2150",
    "X1": "810",
    "X2": "1100",
    "NormalX": "1",
    "NormalY": "1",
    "Y": "2220",
    "Team": "1"
   }
  },
  "Rotation": {
   "count": 209,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "MovingPlatform": {
   "count": 166,
   "attributes": [
    [
     "PlatID",
     166
    ],
    [
     "X",
     87
    ],
    [
     "Y",
     87
    ]
   ],
   "children": [
    "Platform",
    "Animation"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "PlatID": "1",
    "X": "800",
    "Y": "0.000000"
   }
  },
  "Animation": {
   "count": 166,
   "attributes": [
    [
     "NumFrames",
     143
    ],
    [
     "SlowMult",
     140
    ],
    [
     "CenterY",
     8
    ],
    [
     "StartFrame",
     5
    ],
    [
     "CenterX",
     2
    ]
   ],
   "children": [
    "KeyFrame",
    "Phase"
   ],
   "parents": [
    "MovingPlatform"
   ],
   "text": false,
   "example": {
    "NumFrames": "3600",
    "SlowMult": "3.0",
    "CenterY": "-500",
    "StartFrame": "20",
    "CenterX": "-1200"
   }
  },
  "DynamicCollision": {
   "count": 166,
   "attributes": [
    [
     "PlatID",
     166
    ],
    [
     "X",
     166
    ],
    [
     "Y",
     166
    ]
   ],
   "children": [
    "HardCollision",
    "NoSlideCollision",
    "SoftCollision",
    "BouncyHardCollision",
    "LavaCollision",
    "PressurePlateCollision",
    "SoftPressurePlateCollision"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "PlatID": "1",
    "X": "0",
    "Y": "0"
   }
  },
  "Background": {
   "count": 122,
   "attributes": [
    [
     "AssetName",
     122
    ],
    [
     "W",
     122
    ],
    [
     "H",
     122
    ],
    [
     "AnimatedAssetName",
     8
    ],
    [
     "HasSkulls",
     2
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "W": "2048",
    "H": "1151",
    "HasSkulls": "True"
   }
  },
  "LevelDesc": {
   "count": 120,
   "attributes": [
    [
     "AssetDir",
     120
    ],
    [
     "LevelName",
     120
    ],
    [
     "NumFrames",
     8
    ],
    [
     "SlowMult",
     8
    ]
   ],
   "children": [
    "NavNode",
    "HardCollision",
    "AnimatedBackground",
    "Platform",
    "Respawn",
    "ItemSpawn",
    "MovingPlatform",
    "DynamicCollision",
    "SoftCollision",
    "Background",
    "CameraBounds",
    "SpawnBotBounds",
    "NoSlideCollision",
    "ItemInitSpawn",
    "DynamicNavNode",
    "LevelSound",
    "TeamItemInitSpawn",
    "WaveData",
    "Goal",
    "LevelAnimation",
    "BouncyHardCollision",
    "DynamicRespawn",
    "DynamicItemSpawn",
    "ItemSet",
    "LevelAnim",
    "TeamScoreboard",
    "ForegroundAsset",
    "LavaCollision",
    "PressurePlateCollision",
    "BouncyNoSlideCollision",
    "GameModeHardCollision",
    "BouncySoftCollision",
    "MudCollision"
   ],
   "parents": [],
   "text": false,
   "example": {
    "AssetDir": "LostLabyrinth",
    "LevelName": "Batavia",
    "NumFrames": "83",
    "SlowMult": "3"
   }
  },
  "CameraBounds": {
   "count": 120,
   "attributes": [
    [
     "X",
     120
    ],
    [
     "Y",
     120
    ],
    [
     "W",
     120
    ],
    [
     "H",
     120
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "-1280",
    "Y": "-62.4",
    "W": "5870",
    "H": "3301.875"
   }
  },
  "SpawnBotBounds": {
   "count": 120,
   "attributes": [
    [
     "X",
     120
    ],
    [
     "Y",
     120
    ],
    [
     "W",
     120
    ],
    [
     "H",
     120
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "-709.55",
    "Y": "1177.35",
    "W": "2000",
    "H": "2216.95"
   }
  },
  "CustomPath": {
   "count": 116,
   "attributes": [],
   "children": [
    "Point"
   ],
   "parents": [
    "WaveData"
   ],
   "text": false,
   "example": {}
  },
  "ItemInitSpawn": {
   "count": 101,
   "attributes": [
    [
     "X",
     101
    ],
    [
     "Y",
     101
    ],
    [
     "W",
     6
    ],
    [
     "H",
     5
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "-25",
    "Y": "100",
    "W": "20",
    "H": "50"
   }
  },
  "DynamicNavNode": {
   "count": 93,
   "attributes": [
    [
     "PlatID",
     93
    ],
    [
     "X",
     93
    ],
    [
     "Y",
     93
    ]
   ],
   "children": [
    "NavNode"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "PlatID": "1",
    "X": "0",
    "Y": "0"
   }
  },
  "LevelSound": {
   "count": 92,
   "attributes": [
    [
     "SoundEventName",
     92
    ],
    [
     "Interval",
     92
    ],
    [
     "Delay",
     92
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "Interval": "999999999",
    "Delay": "139024"
   }
  },
  "BouncyHardCollision": {
   "count": 72,
   "attributes": [
    [
     "Y1",
     55
    ],
    [
     "Y2",
     55
    ],
    [
     "X1",
     53
    ],
    [
     "X2",
     53
    ],
    [
     "X",
     19
    ],
    [
     "Y",
     17
    ],
    [
     "NormalX",
     3
    ]
   ],
   "children": [],
   "parents": [
    "DynamicCollision",
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "720",
    "Y1": "-250",
    "Y2": "400",
    "X1": "-400",
    "X2": "-400",
    "Y": "-6000",
    "NormalX": "1"
   }
  },
  "TeamItemInitSpawn": {
   "count": 58,
   "attributes": [
    [
     "X",
     58
    ],
    [
     "Y",
     58
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "1150",
    "Y": "1400"
   }
  },
  "WaveData": {
   "count": 54,
   "attributes": [
    [
     "ID",
     54
    ],
    [
     "Speed",
     54
    ],
    [
     "Speed3",
     27
    ],
    [
     "Speed4",
     27
    ],
    [
     "LoopIdx",
     10
    ]
   ],
   "children": [
    "Group",
    "CustomPath"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "ID": "0",
    "Speed": "16",
    "Speed3": "7.5",
    "Speed4": "9",
    "LoopIdx": "2"
   }
  },
  "Goal": {
   "count": 48,
   "attributes": [
    [
     "H",
     48
    ],
    [
     "Team",
     48
    ],
    [
     "W",
     48
    ],
    [
     "X",
     48
    ],
    [
     "Y",
     48
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "H": "400",
    "Team": "1",
    "W": "400",
    "X": "-210",
    "Y": "1708"
   }
  },
  "LavaCollision": {
   "count": 43,
   "attributes": [
    [
     "LavaPower",
     43
    ],
    [
     "X1",
     25
    ],
    [
     "X2",
     25
    ],
    [
     "Y1",
     22
    ],
    [
     "Y2",
     22
    ],
    [
     "Y",
     21
    ],
    [
     "X",
     18
    ],
    [
     "NormalX",
     16
    ],
    [
     "NormalY",
     12
    ]
   ],
   "children": [],
   "parents": [
    "DynamicCollision",
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "LavaPower": "LavaBurn",
    "X1": "-1160",
    "X2": "-1210",
    "Y": "200",
    "X": "5000",
    "Y1": "200",
    "Y2": "-1500",
    "NormalY": "-1",
    "NormalX": "1"
   }
  },
  "LevelAnimation": {
   "count": 28,
   "attributes": [
    [
     "AnimationName",
     28
    ],
    [
     "FileName",
     28
    ],
    [
     "Interval",
     28
    ],
    [
     "PositionX",
     28
    ],
    [
     "PositionY",
     28
    ],
    [
     "Scale",
     28
    ],
    [
     "InitDelay",
     20
    ],
    [
     "PlayMidground",
     16
    ],
    [
     "IntervalRand",
     12
    ],
    [
     "IgnoreOnBlurBG",
     12
    ],
    [
     "Flip",
     12
    ],
    [
     "PlayBackground",
     8
    ],
    [
     "LoopIterations",
     8
    ],
    [
     "Rotation",
     8
    ],
    [
     "PlatID",
     7
    ],
    [
     "RandX",
     4
    ],
    [
     "RandY",
     4
    ],
    [
     "PlayForeground",
     4
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "PlayBackground": "true",
    "Interval": "40064",
    "IntervalRand": "1000",
    "PositionX": "4695",
    "PositionY": "2022",
    "Scale": "1.12",
    "RandX": "200",
    "RandY": "50",
    "PlatID": "7",
    "IgnoreOnBlurBG": "false",
    "Flip": "true",
    "PlayMidground": "true",
    "InitDelay": "9952",
    "LoopIterations": "39",
    "Rotation": "3.15",
    "PlayForeground": "true"
   }
  },
  "DynamicRespawn": {
   "count": 25,
   "attributes": [
    [
     "PlatID",
     25
    ],
    [
     "X",
     25
    ],
    [
     "Y",
     25
    ]
   ],
   "children": [
    "Respawn"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "PlatID": "1",
    "X": "518",
    "Y": "1500"
   }
  },
  "DynamicItemSpawn": {
   "count": 25,
   "attributes": [
    [
     "PlatID",
     25
    ],
    [
     "X",
     25
    ],
    [
     "Y",
     25
    ]
   ],
   "children": [
    "ItemSpawn"
   ],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "PlatID": "2",
    "X": "518",
    "Y": "0"
   }
  },
  "Phase": {
   "count": 23,
   "attributes": [
    [
     "StartFrame",
     23
    ]
   ],
   "children": [
    "KeyFrame"
   ],
   "parents": [
    "Animation"
   ],
   "text": false,
   "example": {
    "StartFrame": "33"
   }
  },
  "PressurePlateCollision": {
   "count": 18,
   "attributes": [
    [
     "AnimOffsetX",
     18
    ],
    [
     "AnimOffsetY",
     18
    ],
    [
     "AssetName",
     18
    ],
    [
     "Cooldown",
     18
    ],
    [
     "FaceLeft",
     18
    ],
    [
     "FireOffsetX",
     18
    ],
    [
     "FireOffsetY",
     18
    ],
    [
     "TrapPowers",
     18
    ],
    [
     "X1",
     17
    ],
    [
     "X2",
     17
    ],
    [
     "Y",
     17
    ],
    [
     "PlatID",
     14
    ],
    [
     "AnimRotation",
     1
    ],
    [
     "X",
     1
    ],
    [
     "Y1",
     1
    ],
    [
     "Y2",
     1
    ]
   ],
   "children": [],
   "parents": [
    "DynamicCollision",
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "AnimOffsetX": "6515",
    "AnimOffsetY": "0",
    "Cooldown": "1920",
    "FaceLeft": "TRUE",
    "FireOffsetX": "6515",
    "FireOffsetY": "1760",
    "PlatID": "3",
    "TrapPowers": "ClimbTrap",
    "X1": "4680",
    "X2": "4820",
    "Y": "0",
    "AnimRotation": "90",
    "X": "2570",
    "Y1": "-760",
    "Y2": "-970"
   }
  },
  "ItemSet": {
   "count": 12,
   "attributes": [
    [
     "X",
     12
    ],
    [
     "Y",
     12
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "1200",
    "Y": "1190"
   }
  },
  "LevelAnim": {
   "count": 10,
   "attributes": [
    [
     "InstanceName",
     10
    ],
    [
     "AssetName",
     10
    ],
    [
     "X",
     10
    ],
    [
     "Y",
     10
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "-1379.4",
    "Y": "1304.7"
   }
  },
  "TeamScoreboard": {
   "count": 8,
   "attributes": [
    [
     "RedTeamX",
     8
    ],
    [
     "BlueTeamX",
     8
    ],
    [
     "Y",
     8
    ],
    [
     "DoubleDigitsOnesX",
     8
    ],
    [
     "DoubleDigitsTensX",
     8
    ],
    [
     "DoubleDigitsY",
     8
    ],
    [
     "DoubleDigitsScale",
     8
    ],
    [
     "RedDigitFont",
     8
    ],
    [
     "BlueDigitFont",
     8
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "RedTeamX": "1044",
    "BlueTeamX": "1301",
    "Y": "2228",
    "DoubleDigitsOnesX": "47",
    "DoubleDigitsTensX": "-10",
    "DoubleDigitsY": "2256",
    "DoubleDigitsScale": "1",
    "RedDigitFont": "SwapJotunRed",
    "BlueDigitFont": "SwapJotunBlue"
   }
  },
  "ForegroundAsset": {
   "count": 8,
   "attributes": [
    [
     "AssetName",
     8
    ],
    [
     "Scale",
     8
    ],
    [
     "X",
     8
    ],
    [
     "Y",
     8
    ],
    [
     "W",
     8
    ],
    [
     "H",
     8
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "Scale": "1.2",
    "X": "1390",
    "Y": "2453",
    "W": "1400",
    "H": "670"
   }
  },
  "ForceDraw": {
   "count": 8,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "SoftPressurePlateCollision": {
   "count": 3,
   "attributes": [
    [
     "AnimOffsetX",
     3
    ],
    [
     "AnimOffsetY",
     3
    ],
    [
     "AssetName",
     3
    ],
    [
     "Cooldown",
     3
    ],
    [
     "FaceLeft",
     3
    ],
    [
     "FireOffsetX",
     3
    ],
    [
     "FireOffsetY",
     3
    ],
    [
     "PlatID",
     3
    ],
    [
     "TrapPowers",
     3
    ],
    [
     "X1",
     3
    ],
    [
     "X2",
     3
    ],
    [
     "Y",
     3
    ]
   ],
   "children": [],
   "parents": [
    "DynamicCollision"
   ],
   "text": false,
   "example": {
    "AnimOffsetX": "200",
    "AnimOffsetY": "0",
    "Cooldown": "1920",
    "FaceLeft": "false",
    "FireOffsetX": "200",
    "FireOffsetY": "0",
    "PlatID": "1",
    "X1": "130",
    "X2": "270",
    "Y": "0"
   }
  },
  "Loops": {
   "count": 3,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "BouncyNoSlideCollision": {
   "count": 2,
   "attributes": [
    [
     "X",
     2
    ],
    [
     "Y1",
     2
    ],
    [
     "Y2",
     2
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "-400",
    "Y1": "-2750",
    "Y2": "-4750"
   }
  },
  "GameModeHardCollision": {
   "count": 2,
   "attributes": [
    [
     "X",
     2
    ],
    [
     "Y1",
     2
    ],
    [
     "Y2",
     2
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X": "2660",
    "Y1": "1280",
    "Y2": "1630"
   }
  },
  "SoundString": {
   "count": 2,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "SoundFrame": {
   "count": 2,
   "attributes": [],
   "children": [],
   "parents": [
    "AnimatedBackground"
   ],
   "text": true,
   "example": {}
  },
  "BouncySoftCollision": {
   "count": 1,
   "attributes": [
    [
     "X1",
     1
    ],
    [
     "X2",
     1
    ],
    [
     "Y1",
     1
    ],
    [
     "Y2",
     1
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X1": "-460",
    "X2": "-20",
    "Y1": "870",
    "Y2": "950"
   }
  },
  "MudCollision": {
   "count": 1,
   "attributes": [
    [
     "X1",
     1
    ],
    [
     "X2",
     1
    ],
    [
     "Y",
     1
    ],
    [
     "NormalY",
     1
    ],
    [
     "MudPower",
     1
    ],
    [
     "MudFallMult",
     1
    ],
    [
     "MudFallStunMult",
     1
    ],
    [
     "MudXSpeedMult",
     1
    ],
    [
     "MudKillDepth",
     1
    ],
    [
     "MudJumpBack",
     1
    ]
   ],
   "children": [],
   "parents": [
    "LevelDesc"
   ],
   "text": false,
   "example": {
    "X1": "-5000.0",
    "X2": "5000.0",
    "Y": "2450.0",
    "NormalY": "-1",
    "MudPower": "MudSplash",
    "MudFallMult": "0.1",
    "MudXSpeedMult": "0.2",
    "MudKillDepth": "200",
    "MudJumpBack": "true"
   }
  }
 },
 "level": {
  "rows": 163,
  "fields": [
   [
    "DisplayName",
    "text",
    163,
    ""
   ],
   [
    "TeamColorOrder",
    "text",
    9,
    ""
   ],
   [
    "AvoidTeamColor",
    "text",
    9,
    ""
   ],
   [
    "FileName",
    "text",
    156,
    ""
   ],
   [
    "AssetName",
    "text",
    156,
    ""
   ],
   [
    "CrateColorA",
    "int",
    142,
    "0x09FAFF"
   ],
   [
    "CrateColorB",
    "int",
    142,
    "0xFEB7BB"
   ],
   [
    "LeftKill",
    "int",
    162,
    "700"
   ],
   [
    "RightKill",
    "int",
    162,
    "700"
   ],
   [
    "TopKill",
    "int",
    162,
    "800"
   ],
   [
    "BottomKill",
    "int",
    162,
    "850"
   ],
   [
    "LevelID",
    "int",
    163,
    "0"
   ],
   [
    "BGMusic",
    "text",
    152,
    ""
   ],
   [
    "StreamerBGMusic",
    "text",
    3,
    ""
   ],
   [
    "StartFrame",
    "int",
    24,
    "0"
   ],
   [
    "MidgroundTint",
    "int",
    1,
    "0xFFFFFF"
   ],
   [
    "MidgroundOffset",
    "int",
    1,
    "0xFFFFFF"
   ],
   [
    "MidgroundFraction",
    "number",
    1,
    "0.5"
   ],
   [
    "MinNumOnlineGamesBeforeRandom",
    "int",
    20,
    "20"
   ],
   [
    "BotTint",
    "int",
    132,
    "0"
   ],
   [
    "BotOffset",
    "int",
    143,
    "0x0065B1"
   ],
   [
    "BotFraction",
    "number",
    132,
    "0.44"
   ],
   [
    "AIStrictRecover",
    "bool",
    15,
    "FALSE"
   ],
   [
    "IsClimbMap",
    "bool",
    3,
    "True"
   ],
   [
    "ShowPlatsDuringMove",
    "bool",
    8,
    "false"
   ],
   [
    "ShowLavaLevelDuringMove",
    "bool",
    2,
    "false"
   ],
   [
    "NegateOverlaps",
    "bool",
    10,
    "false"
   ],
   [
    "AllowItemSpawnOverlap",
    "bool",
    7,
    "false"
   ],
   [
    "ThumbnailPNGFile",
    "text",
    162,
    ""
   ],
   [
    "FixedCamera",
    "bool",
    15,
    "true"
   ],
   [
    "FixedWidth",
    "bool",
    8,
    "TRUE"
   ],
   [
    "FixedWidthYOffset",
    "number",
    1,
    "75"
   ],
   [
    "HardLeftKill",
    "bool",
    12,
    "true"
   ],
   [
    "HardRightKill",
    "bool",
    12,
    "true"
   ],
   [
    "ShadowTint",
    "number",
    0,
    ""
   ],
   [
    "AIPanicLine",
    "number",
    4,
    "1900"
   ],
   [
    "AIGroundLine",
    "number",
    3,
    "1600"
   ],
   [
    "SoftTopKill",
    "bool",
    7,
    "false"
   ],
   [
    "ColorExclusionList",
    "text",
    107,
    ""
   ],
   [
    "BulletWaves",
    "text",
    0,
    ""
   ]
  ],
  "attributes": [
   [
    "DevOnly",
    "bool",
    159,
    "false"
   ],
   [
    "TestLevel",
    "bool",
    159,
    "false"
   ]
  ],
  "sets": [
   "Auto",
   "StandardAll",
   "StandardFFA",
   "Standard1v1",
   "Standard2v2",
   "StandardBig",
   "StreetBrawl",
   "BrawlballSmall",
   "BrawlballBig",
   "BombsketballAll",
   "SoccerNewMap",
   "VolleyballAll",
   "Standard3v3",
   "RicochetBig",
   "PracticeCatchBombs",
   "RicochetFFA",
   "ColorPlatformsAll",
   "Tutorial1",
   "Tutorial2",
   "Tutorial3",
   "Experimental1v1",
   "CTF3v3",
   "Tournament1v1",
   "Tournament2v2",
   "1v1StrikeoutBotW",
   "SoccerAll",
   "FFA3GhostBotW",
   "HordeAll",
   "BuddyAll",
   "BuddyBotW",
   "RingAll",
   "ClimbAll",
   "ShiftBotW",
   "Shift2v2BotW",
   "SoccerSynthOnlyBotW",
   "Showdown",
   "Zombie",
   "Soccer3v3",
   "BrawlballNorseOnlyBotW",
   "ShowdownTrapsOnly",
   "Soccer2v2Ranked",
   "CrewBattleTMNTOnlyBotW",
   "Ranked3v3BrawlballOGMapOnly",
   "GhostBrawl2v2LionOnlyBotW",
   "ClimbBloodMoonOnlyBotW",
   "GIDoeJoeOnlyBotW",
   "BustlingSideStreetOnlyBotW",
   "Tournament3v3",
   "LevelSet_BP6FFA",
   "RooftopOnlyBOTW",
   "RooftopBothBOTW",
   "BataviaBOTW",
   "AvatarBigBOTW",
   "AvatarOnlyBOTW",
   "Soccer3v3Ranked",
   "TableTopALL",
   "TableTopFFA",
   "TableTop1v1",
   "TableTop2v2",
   "TableTopBig",
   "TableTop3v3",
   "BP7MapBOTW",
   "VolleyBattle",
   "HordeBOTW",
   "NewMapFFA",
   "NewMap1v1",
   "NewMapBig",
   "LavaMaps",
   "NewMapNoCeiling1v1",
   "NewMapVolleyBattle",
   "NewMap2v2",
   "Refinery",
   "BombMania",
   "Ranked1v1",
   "Ranked2v2",
   "TableTopNewMap",
   "Crazy",
   "TutorialMaps",
   "RefinerySmall",
   "HordeBasic",
   "AltFFA",
   "SnowbrawlNewSmall",
   "SnowbrawlNewBig",
   "Unranked2v2",
   "GameModeAll",
   "NewMap3v3",
   "Dynamic1v1",
   "DynamicFFA",
   "Dynamic2v2",
   "FortressOfWolves1v1",
   "CelestialLongSidesShortWalls"
  ]
 }
};
