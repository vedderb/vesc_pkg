#!/usr/bin/env python3
# Package an ESP32-S3 (Xtensa) native library into a relocatable container.
#
# Xtensa cannot generate position-independent code: address constants are
# stored as absolute words (R_XTENSA_32) in literal pools and data. The
# library is therefore linked at address 0 with relocations kept (ld -q),
# and the firmware copies the image into RAM and adds the load address to
# every such word at load time. Words that point into executable sections
# get the IRAM alias of the load address, all others the byte-accessible
# DRAM alias (on the S3 the same RAM is mapped at both).
#
# Container layout (all little-endian u32):
#   magic        0xCAFEBABF (NATIVE_LIB_RELOC_MAGIC)
#   image_size   size of image[] in bytes
#   entry_offset offset of the init function inside image[]
#   reloc_count  number of entries in relocs[]
#   relocs[]     (image_offset & 0x7FFFFFFF) | 0x80000000 if the word
#                points into an executable section
#   image[]      0xCAFEBABE magic word followed by the raw binary
#                (ELF VMA v lives at image offset v + 4)
#
# Usage: mkreloc.py <lib.elf> <lib_raw.bin> <out.bin>

import struct
import sys

R_XTENSA_NONE = 0
R_XTENSA_32 = 1
R_XTENSA_ASM_EXPAND = 11
R_XTENSA_ASM_SIMPLIFY = 12
R_XTENSA_SLOT0_OP = 20

# Types that need no load-time patching: PC-relative or informational
# (the ASM_* types just annotate longcall sequences for linker relaxation).
NO_PATCH_TYPES = {R_XTENSA_NONE, R_XTENSA_ASM_EXPAND, R_XTENSA_ASM_SIMPLIFY,
                  R_XTENSA_SLOT0_OP}

SHF_ALLOC = 0x2
SHF_EXECINSTR = 0x4
SHT_RELA = 4
SHT_SYMTAB = 2

NATIVE_LIB_MAGIC = 0xCAFEBABE
NATIVE_LIB_RELOC_MAGIC = 0xCAFEBABF


def fail(msg):
    sys.stderr.write("mkreloc.py: error: %s\n" % msg)
    sys.exit(1)


def read_elf(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        fail("%s is not a little-endian ELF32 file" % path)
    e_shoff, = struct.unpack_from("<I", data, 0x20)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        (sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size, sh_link,
         sh_info, _sh_addralign, sh_entsize) = struct.unpack_from("<10I", data, off)
        sections.append({
            "name_off": sh_name, "type": sh_type, "flags": sh_flags,
            "addr": sh_addr, "offset": sh_offset, "size": sh_size,
            "link": sh_link, "info": sh_info, "entsize": sh_entsize,
        })

    shstr = sections[e_shstrndx]
    for s in sections:
        end = data.index(b"\x00", shstr["offset"] + s["name_off"])
        s["name"] = data[shstr["offset"] + s["name_off"]:end].decode()

    return data, sections


def main():
    if len(sys.argv) != 4:
        fail("usage: mkreloc.py <lib.elf> <lib_raw.bin> <out.bin>")
    elf_path, bin_path, out_path = sys.argv[1:4]

    data, sections = read_elf(elf_path)
    image_bin = open(bin_path, "rb").read()

    alloc_sections = [s for s in sections if s["flags"] & SHF_ALLOC and s["size"] > 0]

    def addr_is_exec(addr):
        for s in alloc_sections:
            if s["addr"] <= addr < s["addr"] + s["size"]:
                return bool(s["flags"] & SHF_EXECINSTR)
        # Allow pointers to the very end of a section (one-past-the-end).
        for s in alloc_sections:
            if addr == s["addr"] + s["size"]:
                return bool(s["flags"] & SHF_EXECINSTR)
        fail("relocation target 0x%X is outside every allocated section" % addr)

    # Symbol tables, keyed by section index.
    symtabs = {}
    for i, s in enumerate(sections):
        if s["type"] == SHT_SYMTAB:
            syms = []
            count = s["size"] // 16
            for j in range(count):
                st_name, st_value, st_size, st_info, st_other, st_shndx = \
                    struct.unpack_from("<IIIBBH", data, s["offset"] + j * 16)
                syms.append({"name_off": st_name, "value": st_value,
                             "shndx": st_shndx, "strtab": s["link"]})
            symtabs[i] = syms

    def sym_name(symtab_idx, sym):
        strtab = sections[symtabs_link[symtab_idx]]
        end = data.index(b"\x00", strtab["offset"] + sym["name_off"])
        return data[strtab["offset"] + sym["name_off"]:end].decode()

    symtabs_link = {i: sections[i]["link"] for i in symtabs}

    # Find the entry symbol.
    entry_vma = None
    for i, syms in symtabs.items():
        for sym in syms:
            if sym["name_off"] and sym_name(i, sym) == "init":
                entry_vma = sym["value"]
    if entry_vma is None:
        fail("no 'init' symbol in %s" % elf_path)
    if entry_vma & 3:
        fail("init is not 4-byte aligned (0x%X)" % entry_vma)

    # Region split: executable sections form the code region at the start
    # of the address space, everything else (led by .program_ptr) the data
    # region. The loader places them in different kinds of RAM: code in
    # any executable block (word-access only), data in any byte-accessible
    # block. Stored words are rewritten to region-relative offsets so the
    # loader just adds the matching region base.
    exec_secs = [s for s in alloc_sections if s["flags"] & SHF_EXECINSTR]
    data_secs = [s for s in alloc_sections if not s["flags"] & SHF_EXECINSTR]
    if not exec_secs or not data_secs:
        fail("expected both code and data sections")

    code_end = max(s["addr"] + s["size"] for s in exec_secs)
    data_start = min(s["addr"] for s in data_secs)
    data_end = max(s["addr"] + s["size"] for s in data_secs)
    if data_start < code_end:
        fail("data sections overlap the code region - check link_esp32s3.ld "
             "section order")
    for s in exec_secs:
        if s["addr"] + s["size"] > data_start:
            fail("code section %s extends into the data region" % s["name"])
    pp = [s for s in data_secs if s["name"] == ".program_ptr"]
    if not pp or pp[0]["addr"] != data_start:
        fail(".program_ptr must lead the data region")

    if entry_vma >= code_end:
        fail("init is not in the code region")

    code_size = (code_end + 3) & ~3
    data_size = ((data_end - data_start + 3) & ~3) + 4  # + inner magic

    def region_of(addr):
        # One-past-the-end pointers of the last code section still count
        # as code; anything from data_start on is data.
        if addr <= code_end:
            return "code", addr
        if data_start <= addr <= data_end:
            return "data", addr - data_start + 4
        fail("address 0x%X falls between the code and data regions" % addr)

    # The linker fully resolves every R_XTENSA_32 word in the binary, but
    # the relocation entries emitted by ld -q can carry stale addends (not
    # adjusted for input-section placement). So the relocation entry is
    # only trusted for WHERE an absolute word lives (r_offset); the target
    # address is read from the resolved word itself.
    image_bin = bytearray(image_bin)
    if len(image_bin) < data_end:
        image_bin += b"\x00" * (data_end - len(image_bin))  # .bss

    relocs = []
    for s in sections:
        if s["type"] != SHT_RELA:
            continue
        target = sections[s["info"]]
        if not target["flags"] & SHF_ALLOC:
            continue
        count = s["size"] // 12
        for j in range(count):
            r_offset, r_info, _r_addend = struct.unpack_from(
                "<IIi", data, s["offset"] + j * 12)
            r_type = r_info & 0xFF
            if r_type in NO_PATCH_TYPES:
                continue
            if r_type != R_XTENSA_32:
                fail("unsupported relocation type %d at 0x%X in %s "
                     "(cannot be fixed up at load time)"
                     % (r_type, r_offset, s["name"]))

            if r_offset & 3:
                fail("R_XTENSA_32 at unaligned offset 0x%X" % r_offset)
            if r_offset + 4 > len(image_bin):
                fail("relocation at 0x%X is outside the binary" % r_offset)

            target_addr, = struct.unpack_from("<I", image_bin, r_offset)
            tgt_region, tgt_off = region_of(target_addr)
            site_region, site_off = region_of(r_offset)
            if site_off >= 1 << 30:
                fail("relocation offset 0x%X too large" % site_off)

            # Rewrite the word to its region-relative target offset.
            struct.pack_into("<I", image_bin, r_offset, tgt_off)

            entry = site_off
            if site_region == "data":
                entry |= 0x40000000
            if tgt_region == "code":
                entry |= 0x80000000
            relocs.append(entry)

    relocs = sorted(set(relocs), key=lambda e: e & 0x7FFFFFFF)
    offs = [(e & 0x7FFFFFFF) for e in relocs]
    if len(offs) != len(set(offs)):
        fail("conflicting classification for one relocation offset")

    code_img = bytes(image_bin[:code_end])
    code_img += b"\x00" * (code_size - len(code_img))
    # Magic words are stored as big-endian bytes (CA FE BA Bx), matching
    # the existing XIP container convention. The data region carries the
    # inner magic so prog_ptr lands at data base + 4.
    data_img = struct.pack(">I", NATIVE_LIB_MAGIC) \
        + bytes(image_bin[data_start:data_end])
    data_img += b"\x00" * (data_size - len(data_img))

    out = struct.pack(">I", NATIVE_LIB_RELOC_MAGIC)
    out += struct.pack("<5I", 2, code_size, data_size, entry_vma, len(relocs))
    out += b"".join(struct.pack("<I", e) for e in relocs)
    out += code_img
    out += data_img

    open(out_path, "wb").write(out)
    print("mkreloc.py: %s: code %d B, data %d B, entry at 0x%X, %d relocations"
          % (out_path, code_size, data_size, entry_vma, len(relocs)))


if __name__ == "__main__":
    main()
