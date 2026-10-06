#!/usr/bin/env python3
"""AdGuard Home For Android —— 模块打包脚本

这个脚本存在的唯一理由，是把三个已经踩过的坑固化下来：

1. 文本文件必须转成 LF。仓库里是 LF，但 Windows 工作区因 core.autocrlf=true
   会显示成 CRLF；若直接打包工作区文件，Android 的 mksh 每行都会带上游离的
   \\r，shebang 和所有命令都无法正确解析，安装直接失败。
2. 必须包含 META-INF/com/google/android/update-binary。这是 Magisk 的安装入口，
   缺了会报 unzip error。仓库原本没有这个目录（作者发布 zip 时手动补的）。
3. 打包后必须用 mksh 做语法校验。sh -n 会把 mksh 专有语法误报为错误，
   bash -n 通过也不代表设备上能跑，只有 mksh 通过才算数。

用法：
    python tools/pack_module.py                      # 用 module.prop 里的版本号
    python tools/pack_module.py --version 20261006   # 指定版本号
    python tools/pack_module.py --out D:\\dist\\x.zip # 指定输出路径
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile

# 统一以 UTF-8 输出；Windows 传统控制台若乱码可先执行 chcp 65001
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Adguardhome")

TEXT_EXT = (".sh", ".prop", ".yaml", ".yml", ".txt", ".json", ".conf")
SKIP_NAMES = {".DS_Store", "Thumbs.db", "desktop.ini"}
SKIP_DIRS = {".git", "__pycache__", ".pack"}
UPDATE_BINARY = os.path.join("META-INF", "com", "google", "android", "update-binary")
CORE_BINARY = os.path.join("bin", "AdGuardHome")


def die(msg):
    print("[FAIL] %s" % msg)
    sys.exit(1)


def info(msg):
    print("[ OK ] %s" % msg)


def warn(msg):
    print("[WARN] %s" % msg)


def read_prop_version():
    path = os.path.join(SRC, "module.prop")
    if not os.path.isfile(path):
        die("缺少 module.prop，无法确定版本号")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("version="):
                return line.split("=", 1)[1].strip()
    die("module.prop 中没有 version= 字段")

def collect():
    """按稳定顺序收集待打包文件，目录条目在前，保证解压顺序可控。"""
    files = []
    for base, dirs, names in os.walk(SRC):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        rel_base = os.path.relpath(base, SRC)
        if rel_base != ".":
            files.append((base, rel_base.replace(os.sep, "/") + "/", True))
        for name in sorted(names):
            if name in SKIP_NAMES:
                continue
            full = os.path.join(base, name)
            files.append((full, os.path.relpath(full, SRC).replace(os.sep, "/"), False))
    return files


def to_lf(data):
    """Android 的 mksh 不容忍 CRLF：shebang 与每行命令都会带上游离的 CR。"""
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def build(out_path):
    if not os.path.isdir(SRC):
        die("未找到模块目录 %s" % SRC)

    # 前置检查：这两项缺失都会导致刷入直接失败
    if not os.path.isfile(os.path.join(SRC, UPDATE_BINARY)):
        die("缺少 Magisk 安装入口 %s（缺失会报 unzip error）" % UPDATE_BINARY)
    info("Magisk 安装入口存在")

    core = os.path.join(SRC, CORE_BINARY)
    has_core = os.path.isfile(core) and os.path.getsize(core) > 0
    if has_core:
        info("核心二进制存在（%.2f MB）" % (os.path.getsize(core) / 1024 / 1024))
    else:
        warn("缺少核心二进制 bin/AdGuardHome —— 该包无法独立刷入，发布前必须补上")

    files = collect()
    if os.path.exists(out_path):
        os.remove(out_path)

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for full, arc, is_dir in files:
            entry = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
            entry.create_system = 3  # 按 Unix 记录，Android 才认权限位
            entry.external_attr = (0o755 << 16) | (0o40000 if is_dir else 0o100000)
            entry.compress_type = zipfile.ZIP_DEFLATED
            if is_dir:
                zf.writestr(entry, b"")
                continue
            with open(full, "rb") as fh:
                data = fh.read()
            if arc.lower().endswith(TEXT_EXT):
                data = to_lf(data)
            zf.writestr(entry, data)
    return out_path, has_core

def verify(out_path, has_core):
    """对生成的包做与设备侧等价的校验。"""
    ok = True
    mksh = shutil.which("mksh")

    with zipfile.ZipFile(out_path) as zf:
        if zf.testzip():
            warn("CRC 校验失败")
            ok = False
        else:
            info("CRC 校验通过")

        names = zf.namelist()
        required = [
            "META-INF/com/google/android/update-binary",
            "META-INF/com/google/android/updater-script",
            "module.prop", "customize.sh", "service.sh", "action.sh", "uninstall.sh",
        ]
        missing = [r for r in required if r not in names]
        if missing:
            warn("缺少必要条目: %s" % ", ".join(missing))
            ok = False
        else:
            info("必要条目齐全（%d 项）" % len(required))

        cr_files = [n for n in names
                    if not n.endswith("/") and n.lower().endswith(TEXT_EXT)
                    and b"\r" in zf.read(n)]
        if cr_files:
            warn("以下文本文件残留 CR（设备上会执行失败）: %s" % ", ".join(cr_files))
            ok = False
        else:
            info("全部文本文件为 LF")

        scripts = [n for n in names if n.endswith(".sh") or n.endswith("update-binary")]
        if not mksh:
            warn("未找到 mksh，跳过语法校验（建议在 WSL 内安装 mksh 后重跑本脚本）")
        else:
            tmp = os.path.join(os.environ.get("TEMP", "/tmp"), "agh_pack_verify")
            shutil.rmtree(tmp, ignore_errors=True)
            os.makedirs(tmp)
            failed = []
            for name in scripts:
                zf.extract(name, tmp)
                target = os.path.join(tmp, *name.split("/"))
                proc = subprocess.run([mksh, "-n", target], capture_output=True, text=True)
                if proc.returncode != 0:
                    detail = (proc.stderr or proc.stdout).strip().splitlines()
                    failed.append("%s -> %s" % (name, detail[0] if detail else "unknown"))
            shutil.rmtree(tmp, ignore_errors=True)
            if failed:
                warn("mksh 语法校验失败:\n       " + "\n       ".join(failed))
                ok = False
            else:
                info("mksh 语法校验通过（%d 个脚本）" % len(scripts))

        if has_core:
            digest = hashlib.sha256(zf.read("bin/AdGuardHome")).hexdigest()
            info("核心二进制 SHA256 %s" % digest)

    return ok


def main():
    parser = argparse.ArgumentParser(description="打包 AdGuard Home For Android 模块")
    parser.add_argument("--version", help="覆盖 module.prop 中的版本号")
    parser.add_argument("--out", help="输出 zip 路径")
    args = parser.parse_args()

    version = args.version or read_prop_version()
    out_path = args.out or os.path.join(ROOT, "AdGuard.Home.For.Android.%s.zip" % version)

    print("版本: %s" % version)
    print("输出: %s" % out_path)
    print("-" * 62)

    out_path, has_core = build(out_path)
    info("已生成 %s（%.2f MB）" % (os.path.basename(out_path), os.path.getsize(out_path) / 1024 / 1024))

    print("-" * 62)
    ok = verify(out_path, has_core)
    print("-" * 62)
    if not ok:
        die("校验未全部通过，请勿发布")
    if not has_core:
        warn("包内没有核心二进制，仅可用于脚本调试，不能直接刷入")
    print("打包完成：%s" % out_path)


if __name__ == "__main__":
    main()