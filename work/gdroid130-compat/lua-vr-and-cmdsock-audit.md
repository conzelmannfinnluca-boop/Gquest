# VR Lua API and command socket appendix

The old `liblua_shared.so` registered the `vr` table at0x118518..0x118690. The official0.1.30 library contains none of its characteristic Lua names or9VRXR imports. This is an absent binding, not a changed IsActive flag interpretation. Runtime absence was separately measured by the primary agent.

Old IsActive0x118744 always returns true. GetPrimaryHand0x118ba4 forwards the native integer. Full old wrappers are preserved as disassembly in `old-vr-lua-bindings.asm`; precise argument/return contracts and offsets are in `lua-vr-and-cmdsock-audit.json`.

Position conversion is `(x,-z,y)*39.370098`. Quaternion xyzw conversion uses conventional pitch `asin(2*(w*y-z*x))`, yaw `atan2(2*(w*z+x*y),1-2*(y*y+z*z))`, roll `atan2(2*(w*x+y*z),1-2*(x*x+y*y))`, in degrees. FNMSUB sign was independently checked by compiling a focused C expression with the same NDK.

The engine starts its command socket only on the located explicit `-vr_cmdsock_port` path. Default port27100, clamp1..65535, bind127.0.0.1, TCP backlog1. See `new-cmdsock-startup.asm`. This is static evidence, not an observation of a listening socket.
