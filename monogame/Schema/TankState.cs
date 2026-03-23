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

public partial class TankState : Schema {
#if UNITY_5_3_OR_NEWER
[Preserve]
#endif
public TankState() { }
	[Type(0, "string")]
	public string name = default(string);

	[Type(1, "uint8")]
	public byte team = default(byte);

	[Type(2, "float32")]
	public float x = default(float);

	[Type(3, "float32")]
	public float y = default(float);

	[Type(4, "float32")]
	public float angle = default(float);

	[Type(5, "int8")]
	public sbyte hp = default(sbyte);

	[Type(6, "int8")]
	public sbyte shield = default(sbyte);

	[Type(7, "boolean")]
	public bool dead = default(bool);

	[Type(8, "string")]
	public string killer = default(string);

	[Type(9, "uint16")]
	public ushort score = default(ushort);
}

