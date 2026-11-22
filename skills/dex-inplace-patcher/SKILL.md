---
name: dex-inplace-patcher
description: Performs zero-repack, alignment-preserving in-place bytecode patching inside uncompressed (`STORED`) `classes*.dex` entries of Android `.apk` and `.jar` archives. Use when modifying framework jars or privileged system APKs (`telephony-common.jar`, `SystemUI.apk`, `framework.jar`) where `apktool`/re-zipping breaks ART mmap alignment, APK v2/v3 signatures, or system-server dexopt.
---

# DEX In-Place Patcher

Modify single Dalvik opcodes, field IDs, method IDs, or constant instructions directly inside `classes*.dex` bytes without inflating, decompiling/recompiling with smali, or changing the surrounding ZIP container structure.

## When to Use In-Place Patching Instead of `apktool`
- Target is a system framework `.jar` or priv-app `.apk` bind-mounted by KernelSU/Magisk.
- `classes*.dex` is stored uncompressed (`ZIP_STORED`) so Android ART can `mmap()` it at exact 4-byte page alignment.
- You want **100% deterministic, idempotent, zero-repack** patches driven by dynamic symbol lookup rather than hardcoded hex offsets that break on every OTA.

## Core Rules
1. **Verify `compress_type == zipfile.ZIP_STORED`**: Never splice bytes into `ZIP_DEFLATED` entries; only modify byte-for-byte equal-length replacements (`insns_size` untouched) inside `STORED` entries.
2. **Resolve Symbol IDs Dynamically**: Parse DEX `string_ids`, `type_ids`, `field_ids`, `method_ids`, and `class_defs` (`class_data_item` -> ULEB128 encoded `direct_methods` & `virtual_methods`) by exact Java descriptor instead of hardcoding `field_idx` or `method_idx`.
3. **Walk Dalvik Instruction Boundaries Properly**: Never blind-search byte patterns across `insns[]`; payload pseudo-ops (`0x0100`/`0x0200`/`0x0300`) and multi-unit opcodes (`invoke-*` 3 units, `iput-boolean`/`iget-object` 2 units, `const-wide` 5 units) can create false-positive byte matches.
4. **Preserve Verifier Validity & Idempotency**:
   - Check register width & bounds (e.g., `const/4` only encodes 4-bit registers `0..15` and signed literals `-8..7`).
   - Support recognizing the already-patched state so re-running the patcher on a mounted APK succeeds idempotently.
5. **Update All 4 Checksums**:
   - **DEX SHA-1** (`dex[12:32]`): `hashlib.sha1(dex[32:]).digest()`
   - **DEX Adler-32** (`dex[8:12]`): `zlib.adler32(dex[12:]) & 0xFFFFFFFF`
   - **ZIP Local File Header CRC-32** (`lhoff + 14`)
   - **ZIP Central Directory CRC-32** (`cd_entry + 16`)
   - Always finish with `ZipFile.testzip() is None`.

## Dalvik Quick Reference (High-Frequency Patch Opcodes)
- `0x12` (`const/4 vA, #+B`, 1 unit `B|A|op`): `vA = (w0 >> 8) & 0xF`, `lit = (w0 >> 12) & 0xF`
- `0x0F` (`return vAA`, 1 unit `AA|op`): quick constant boolean return with `0x1012, 0x000F` (`return true`) or `0x0012, 0x000F` (`return false`)
- `0x54` / `0x55` (`iget-object` / `iget-boolean`, 2 units): `w1 = field_id`
- `0x5B` / `0x5C` (`iput-object` / `iput-boolean`, 2 units): `w1 = field_id`
- `0x6E..0x72` (`invoke-virtual/super/direct/static/interface`, 3 units): `w1 = method_id`
- `0x26` (`fill-array-data vAA, +BBBBBBBB`, 3 units): points to `0x0300` payload `(ident, elem_width, count, bytes...)`

Use [scripts/dex_patch_template.py](scripts/dex_patch_template.py) as the starting skeleton for new in-place DEX patchers.
