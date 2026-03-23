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

public partial class TeamState : Schema {
#if UNITY_5_3_OR_NEWER
[Preserve]
#endif
public TeamState() { }
	[Type(0, "uint16")]
	public ushort score = default(ushort);

	[Type(1, "uint8")]
	public byte tanks = default(byte);
}

