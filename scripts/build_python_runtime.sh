#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Unseen"
PYTHON_VERSION="3.14"
PYTHON_FRAMEWORK="/Library/Frameworks/Python.framework"
STANDARD_APP="$ROOT/outputs/$APP_NAME.app"
RUNTIME_APP="$ROOT/outputs/$APP_NAME Python Runtime.app"
RUNTIME_ZIP="$ROOT/outputs/$APP_NAME Python Runtime.zip"
CONTENTS="$RUNTIME_APP/Contents"
PYTHON_ROOT="$CONTENTS/Frameworks/Python.framework/Versions/$PYTHON_VERSION"
PYTHON_LIB="$PYTHON_ROOT/lib"
PYTHON_DYNLOAD="$PYTHON_LIB/python$PYTHON_VERSION/lib-dynload"
PYTHON_INTERPRETER_SOURCE="$PYTHON_FRAMEWORK/Versions/$PYTHON_VERSION/Resources/Python.app/Contents/MacOS/Python"

if [[ ! -d "$PYTHON_FRAMEWORK/Versions/$PYTHON_VERSION" ]]; then
    echo "Python $PYTHON_VERSION framework not found at $PYTHON_FRAMEWORK" >&2
    exit 1
fi

if [[ "${MAC_UNSEEN_SKIP_STANDARD_BUILD:-0}" != "1" ]]; then
    "$ROOT/scripts/build_app.sh"
fi
if [[ ! -d "$STANDARD_APP" ]]; then
    echo "Standard app not found at $STANDARD_APP" >&2
    exit 1
fi
rm -rf "$RUNTIME_APP" "$RUNTIME_ZIP"
ditto "$STANDARD_APP" "$RUNTIME_APP"

mkdir -p "$CONTENTS/Frameworks" "$CONTENTS/Resources/Licenses"
ditto "$PYTHON_FRAMEWORK" "$CONTENTS/Frameworks/Python.framework"

# The sensor helper never uses Python's Tk GUI stack. Removing these nested
# frameworks keeps the runtime smaller and allows the relocated framework to
# be signed consistently on current macOS releases.
rm -rf \
    "$PYTHON_ROOT/Frameworks/Tcl.framework" \
    "$PYTHON_ROOT/Frameworks/Tk.framework" \
    "$PYTHON_ROOT/lib/python$PYTHON_VERSION/tkinter" \
    "$PYTHON_ROOT/lib/python$PYTHON_VERSION/idlelib" \
    "$PYTHON_ROOT/lib/python$PYTHON_VERSION/turtledemo"
find "$PYTHON_ROOT/lib/python$PYTHON_VERSION/lib-dynload" \
    -name '_tkinter*.so' -delete

if [[ ! -x "$PYTHON_INTERPRETER_SOURCE" ]]; then
    echo "Python interpreter not found at $PYTHON_INTERPRETER_SOURCE" >&2
    exit 1
fi
install -m 755 \
    "$PYTHON_INTERPRETER_SOURCE" \
    "$CONTENTS/Resources/python3.bin"
# The python.org bin/python3 launcher delegates to Python.app, whose load path
# points back to /Library. Use Python.app's actual interpreter executable as
# our native launcher, then remove the now-unused nested app from the bundle.
rm -rf "$PYTHON_ROOT/Resources/Python.app"
install_name_tool -change \
    "/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION/Python" \
    "@executable_path/../Frameworks/Python.framework/Versions/$PYTHON_VERSION/Python" \
    "$CONTENTS/Resources/python3.bin"

# python.org's extension modules and support libraries retain install names
# rooted at /Library. They work on a development Mac with Python installed but
# fail on the clean Macs this build targets, so relocate every library used by
# the advanced-sensor helper to paths relative to its loading module.
for module in "$PYTHON_DYNLOAD"/_zstd*.so; do
    [[ -e "$module" ]] || continue
    install_name_tool -change \
        "/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION/lib/libzstd.1.dylib" \
        "@loader_path/../../libzstd.1.dylib" \
        "$module"
done
for module in "$PYTHON_DYNLOAD"/_hashlib*.so; do
    [[ -e "$module" ]] || continue
    install_name_tool -change \
        "/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION/lib/libcrypto.3.dylib" \
        "@loader_path/../../libcrypto.3.dylib" \
        "$module"
done
for module in "$PYTHON_DYNLOAD"/_ssl*.so; do
    [[ -e "$module" ]] || continue
    install_name_tool -change \
        "/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION/lib/libssl.3.dylib" \
        "@loader_path/../../libssl.3.dylib" \
        "$module"
    install_name_tool -change \
        "/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION/lib/libcrypto.3.dylib" \
        "@loader_path/../../libcrypto.3.dylib" \
        "$module"
done
install_name_tool -change \
    "/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION/lib/libcrypto.3.dylib" \
    "@loader_path/libcrypto.3.dylib" \
    "$PYTHON_LIB/libssl.3.dylib"
install_name_tool -id "@loader_path/libzstd.1.dylib" \
    "$PYTHON_LIB/libzstd.1.5.7.dylib"
install_name_tool -id "@loader_path/libcrypto.3.dylib" \
    "$PYTHON_LIB/libcrypto.3.dylib"
install_name_tool -id "@loader_path/libssl.3.dylib" \
    "$PYTHON_LIB/libssl.3.dylib"

cat > "$CONTENTS/Resources/python3" <<'EOF'
#!/bin/zsh
set -euo pipefail
APP_CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_ROOT="$APP_CONTENTS/Frameworks/Python.framework/Versions/3.14"
export PYTHONHOME="$PYTHON_ROOT"
export PYTHONPATH="$PYTHON_ROOT/lib/python3.14"
exec "$APP_CONTENTS/Resources/python3.bin" "$@"
EOF
chmod 755 "$CONTENTS/Resources/python3"
install -m 644 "$ROOT/Resources/Licenses/Python-3.14-PSF.txt" \
    "$CONTENTS/Resources/Licenses/Python-3.14-PSF.txt"

# install_name_tool invalidates the python.org signatures. Explicitly re-sign
# each modified Mach-O file; codesign --deep does not reliably replace invalid
# signatures on nested extension modules.
for module in \
    "$PYTHON_DYNLOAD"/_zstd*.so \
    "$PYTHON_DYNLOAD"/_hashlib*.so \
    "$PYTHON_DYNLOAD"/_ssl*.so
do
    [[ -e "$module" ]] || continue
    codesign --force --sign - "$module"
done
codesign --force --sign - "$PYTHON_LIB/libzstd.1.5.7.dylib"
codesign --force --sign - "$PYTHON_LIB/libcrypto.3.dylib"
codesign --force --sign - "$PYTHON_LIB/libssl.3.dylib"
codesign --force --deep --sign - "$CONTENTS/Frameworks/Python.framework"
codesign --force --sign - "$CONTENTS/Resources/python3.bin"
codesign --force --deep --sign - "$RUNTIME_APP"
codesign --verify --deep --strict --verbose=2 "$RUNTIME_APP"

RUNTIME_IMPORT_CHECK="$(
    PYTHONHOME="$PYTHON_ROOT" \
    PYTHONPATH="$PYTHON_ROOT/lib/python$PYTHON_VERSION" \
    DYLD_PRINT_LIBRARIES=1 \
    "$CONTENTS/Resources/python3.bin" -c \
        'import argparse,collections,copy,ctypes,ctypes.util,json,math,os,re,signal,struct,subprocess,sys,tempfile,threading,time' \
        2>&1
)"
if print -r -- "$RUNTIME_IMPORT_CHECK" \
    | /usr/bin/grep -Fq "/Library/Frameworks/Python.framework"
then
    print -r -- "$RUNTIME_IMPORT_CHECK" >&2
    echo "Bundled Python still loaded an external Python.framework" >&2
    exit 1
fi
"$CONTENTS/Resources/python3" \
    "$CONTENTS/Resources/advanced_sensor_helper.py" --help >/dev/null

ditto -c -k --norsrc --noextattr --keepParent --zlibCompressionLevel 9 \
    "$RUNTIME_APP" "$RUNTIME_ZIP"

echo "$RUNTIME_APP"
echo "$RUNTIME_ZIP"
