// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 4.0.18
// 

using Colyseus.Schema;
#if UNITY_5_3_OR_NEWER
using UnityEngine.Scripting;
#endif

public partial class BattleState : Schema {
#if UNITY_5_3_OR_NEWER
[Preserve]
#endif
public BattleState() { }
	[Type(0, "uint16")]
	public ushort totalScore = default(ushort);

	[Type(1, "int8")]
	public sbyte winnerTeam = default(sbyte);

	[Type(2, "array", typeof(ArraySchema<TeamState>))]
	public ArraySchema<TeamState> teams = null;

	[Type(3, "map", typeof(MapSchema<TankState>))]
	public MapSchema<TankState> tanks = null;

	[Type(4, "map", typeof(MapSchema<BulletState>))]
	public MapSchema<BulletState> bullets = null;

	[Type(5, "map", typeof(MapSchema<PickableState>))]
	public MapSchema<PickableState> pickables = null;
}

