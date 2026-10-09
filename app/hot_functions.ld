/*
 * Section order for the Switch NRO.
 *
 * The Sonic Adventure 2 version of this file listed 1,500 symbols by hotness, taken from a console profile of that
 * game (tools/hot_order.py over logs/rex/rex_profile.log). Those symbols are Sonic Adventure 2's: its Ninja matrix
 * library, its Direct3D internals, its recompiled guest functions. Far Cry 3's code is different, so keeping that
 * order would scatter the functions that are actually hot and waste the A57's 48 KB instruction cache and its small
 * TLB.
 *
 * What does stay is the part that is a requirement and not a measurement:
 *
 *   KEEP (*(.crt0)) first. The NRO is unbootable if the start-up code moves away from address 0 (a section
 *   ordering file did it once on nfsmw-nx, and tools/check_switch_build.py checks for it).
 *
 * Then the C runtime routines, which are hot in every guest that uses memcpy/memset/memmove - the translated game
 * code calls them constantly - and the small set of SDK entry points that run every frame.
 *
 * Regenerate with a real profile before trusting any hotness order: build the NRO, play it, copy the pgo/ and
 * logs/rex/ folders back, then `python tools/hot_order.py <log> <elf> > app/hot_functions.ld`. A Far Cry 3 profile
 * replaces the list below with its own (guia, capitulo 9.2).
 */
.text : {
  KEEP (*(.crt0))
  *libc.a:libc_a-memcpy.o(.text .text.*)
  *libc.a:libc_a-memmove.o(.text .text.*)
  *libc.a:libc_a-memset.o(.text .text.*)
  *libc.a:libc_a-memcmp.o(.text .text.*)
  *(.text.main)
  *(.text._EntryWrap)
  *(.text._ZN3rex2ui24SwitchWindowedAppContext18RunMainMessageLoopEv)
  *(.text.exit)
  *(.text._ZN3rex5audio2nx17SwitchAudioSystem16OutputThreadMainEv)
  *(.text.audoutWaitPlayFinish)
  *(.text.*)
}