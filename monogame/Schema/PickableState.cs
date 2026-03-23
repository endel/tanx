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

public partial class PickableState : Schema {
#if UNITY_5_3_OR_NEWER
[Preserve]
#endif
public PickableState() { }
	[Type(0, "string")]
	public string type = default(string);

	[Type(1, "float32")]
	public float x = default(float);

	[Type(2, "float32")]
	public float y = default(float);
}

