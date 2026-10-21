# GDroid0.1.30 native bridge compatibility audit

Offline evidence only. No headset changes. Ordinary LLVM/ELF tools used because no REA native provider is available.

## Address map

|Bridge dependency|0.1.29 VA|0.1.30 VA|
|---|---|---|
|pose_constructor|`0x3a1428`|`0x46eac4`|
|left_palm_branch|`0x3a164c`|`0x46ece8`|
|finger_blend_call|`0x3a167c`|`0x46ed18`|
|finger_blend_function|`0x3a1118`|`0x46e7b4`|
|local_hand_pose|`0x34b0f8`|`0x4163f0`|
|layer_allocator|`0x322490`|`0x3ed58c`|
|vr_singleton_got|`0xddce48`|`0xf47ae0`|
|material_system_got|`0xddccb0`|`0xf47948`|
|layer_record_array|`0xde39d8`|`0xf4e818`|
|vrplayer_init_patch|`0x4857b0`|`0x552128`|
|input_snapshot_false_stub|`0x174d4`|`0x180f4`|

All five focused functions retain the same instruction counts, mnemonic/register layout and relative control-flow shape. They are **not byte identical**: code/data addresses and page offsets moved. Focused assembly and complete per-function differences are saved beside this report. This does not prove unchanged transitive callees.

## Init patch

New VA `0x552128`, file offset `0x54e128`, expected `e1031f2a`, replacement `21008052`. The ConVar is `hlvr_isvrplayer`, confirmed via constructor0x418a58, GOT0xf47a38 ->0xfac808 and name string0x1564be. Init call0x552134 reaches ConVar int setter thunk0xb388dc.

## Preserved layout

Local pose flags977/4888/5024 and cachedmatrix4896+64*side are unchanged. Left branch and finger call have exact original bytes/target checks. Layer array uses5records of48bytes, texture+16 and surface+24. Material global GOT now0xf47948; VR singleton GOT now0xf47ae0.

InputSystem vtable offset464 remains the snapshot slot; its new false-return stub is0x180f4, identical8bytes. Both client consumers and VRXR producer copy4288bytes. LocateInput(time0) still copies the cached snapshot and returns whether its stamp is nonzero. Pose data starts at+8; complete component semantics were not re-derived.

All7 VRXR symbols referenced by bridge remain exported; implementation sizes sometimes changed. Bootstrap runtime behavior still needs device validation.

Full findings and librarySHA256 values: `audit.json`.
