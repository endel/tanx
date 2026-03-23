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

public partial class BulletState : Schema {
#if UNITY_5_3_OR_NEWER
[Preserve]
#endif
public BulletState() { }
	[Type(0, "string")]
	public string owner = default(string);

	[Type(1, "float32")]
	public float x = default(float);

	[Type(2, "float32")]
	public float y = default(float);

	[Type(3, "float32")]
	public float tx = default(float);

	[Type(4, "float32")]
	public float ty = default(float);

	[Type(5, "float32")]
	public float speed = default(float);

	[Type(6, "boolean")]
	public bool special = default(bool);
}

