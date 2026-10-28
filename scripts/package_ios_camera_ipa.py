"""Package a compiled iPhone app for LOCAL re-signing, never claim install readiness."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import stat
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = ROOT/'firmware/build/ios-camera/DeviceCheck/Build/Products/Debug-iphoneos/MiniBridge Camera.app'
DEFAULT_OUTPUT = ROOT/'artifacts/ios/MiniBridge-Camera-0.2.0-UNSIGNED-resign-required.ipa'


def ios_executable(file):
    with file.open('rb') as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError('Missing Mach-O header')
        magic, cpu, subtype, kind, count, length, flags, reserved = struct.unpack('<IiiIIIII',header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 2 or not 1 <= count <= 4096 or length > 1024*1024:
            raise ValueError('Expected a thin ARM64 iPhone executable, not a simulator or source file')
        commands = stream.read(length)
    offset = 0
    platforms = []
    for _ in range(count):
        if offset + 8 > len(commands):raise ValueError('Truncated load commands')
        command, size = struct.unpack_from('<II',commands,offset)
        if size < 8 or offset + size > len(commands):raise ValueError('Invalid load command length')
        if command == 0x32:
            if size < 24:raise ValueError('Invalid build platform command')
            platforms.append(struct.unpack_from('<I',commands,offset+8)[0])
        offset += size
    if offset != len(commands) or platforms != [2]:
        raise ValueError('Build platform must be iPhoneOS; simulator output cannot be re-labeled')
    return {'architecture':'arm64','platform':'iPhoneOS'}


def package(app, output):
    if Path(app).is_symlink():raise ValueError('Symlink app is not allowed')
    app, output = Path(app).resolve(), Path(output).resolve()
    build_root = (ROOT/'firmware/build').resolve()
    if not app.is_relative_to(build_root) or app.suffix != '.app' or not app.is_dir():
        raise ValueError('Use a compiled .app under firmware/build')
    if not output.is_relative_to(ROOT) or output.is_relative_to(app) or output.suffix != '.ipa':
        raise ValueError('Output must be a separate .ipa inside the workspace')
    files = []
    for file in sorted(app.rglob('*')):
        if file.is_symlink() or not file.resolve().is_relative_to(app):
            raise ValueError('App may not contain symlinks or paths outside its bundle')
        if not file.is_file():continue
        if file.suffix.lower() in ('.p12','.mobileprovision','.pem','.key'):
            raise ValueError('Signing material must not be packaged by the unsigned exporter')
        files.append(file)
    info = plistlib.loads((app/'Info.plist').read_bytes())
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Info.plist does not identify iPhoneOS')
    name = info.get('CFBundleExecutable')
    if not isinstance(name,str) or not name or name in ('.','..') or any(c in name for c in '/\\\x00'):
        raise ValueError('Invalid app executable name')
    binary = ios_executable(app/name)
    output.parent.mkdir(parents=True,exist_ok=True)
    expected = {}
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            relative = 'Payload/'+app.name+'/'+file.relative_to(app).as_posix()
            data = file.read_bytes()
            entry = zipfile.ZipInfo(relative,date_time=(2026,10,27,0,0,0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if file == app/name or file.stat().st_mode & 0o111 else 0o644
            entry.external_attr = (stat.S_IFREG|mode)<<16
            archive.writestr(entry,data)
            expected[relative] = hashlib.sha256(data).hexdigest()
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(expected):
            raise ValueError('IPA integrity check failed')
        for filename,digest in expected.items():
            if hashlib.sha256(archive.read(filename)).hexdigest() != digest:
                raise ValueError('IPA file hash mismatch')
    result = {'kind':'UNSIGNED_IPA_REQUIRES_LOCAL_PERSONAL_SIGNING','install_ready':False,
        'testflight_ready':False,'signed_by_this_script':False,'device_binary':binary,
        'bundle_identifier':info.get('CFBundleIdentifier'),'version':info.get('CFBundleShortVersionString'),
        'build':info.get('CFBundleVersion'),'minimum_ios':info.get('MinimumOSVersion'),
        'path':output.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
        'bytes':output.stat().st_size,'files':expected}
    output.with_suffix('.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,default=DEFAULT_APP)
    parser.add_argument('--output',type=Path,default=DEFAULT_OUTPUT)
    args=parser.parse_args()
    result=package(args.app,args.output)
    print(json.dumps({key:value for key,value in result.items() if key!='files'},indent=2))
