#!/bin/bash
# Shared by build-app.sh (Parrot) and build-wren.sh (Wren): copy every Homebrew dylib a binary
# needs into the bundle's Frameworks dir and rewrite the references to @rpath.
#
# Data-driven on purpose. Bottles rename and re-link between releases (llama.cpp 0.x -> 1.x moved
# libllama.0 -> libllama.1 and switched to @rpath install names; openssl@3 -> openssl@4; ggml 0.23
# added libomp). Any fixed list goes stale and ships an app that dies with "Library not loaded"
# on every Mac without Homebrew.
#
# Usage (after sourcing): FRAMEWORKS=<dir> bundle_closure <binary>
#                         FRAMEWORKS=<dir> bundle_ggml_plugins <dest-dir>

BREW_PREFIX="${BREW_PREFIX:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)}"

# $1 = binary -> "<reference> <resolved Homebrew path>" for each dependency that lives in Homebrew.
# Absolute /opt/homebrew paths resolve to themselves; @rpath/X resolves to <brew>/lib/X when that
# exists (every keg links its dylibs there). System libs and @rpath refs Homebrew doesn't own
# (Sparkle, the bundle's own frameworks) are skipped.
brew_deps() {
    local ref name
    while read -r ref; do
        case "${ref}" in
            "${BREW_PREFIX}"/*) echo "${ref} ${ref}" ;;
            @rpath/*)
                name="${ref#@rpath/}"
                if [ -f "${BREW_PREFIX}/lib/${name}" ]; then echo "${ref} ${BREW_PREFIX}/lib/${name}"; fi
                ;;
        esac
    done < <(otool -L "$1" | awk 'NR>1 {print $1}')
    return 0
}

# $1 = Homebrew dylib path -> copied into $FRAMEWORKS (once), its own deps bundled recursively.
bundle_dylib() {
    local name real
    name="$(basename "$1")"
    [ -f "${FRAMEWORKS}/${name}" ] && return 0
    real="$(readlink -f "$1" 2>/dev/null || realpath "$1")"
    [ -f "${real}" ] || { echo "[!] Missing dylib: $1" >&2; exit 1; }
    cp "${real}" "${FRAMEWORKS}/${name}"
    chmod u+w "${FRAMEWORKS}/${name}"
    install_name_tool -id "@rpath/${name}" "${FRAMEWORKS}/${name}" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path" "${FRAMEWORKS}/${name}" 2>/dev/null || true
    relink_deps "${FRAMEWORKS}/${name}"
}

# $1 = binary inside the bundle -> every Homebrew reference rewritten to @rpath and bundled.
relink_deps() {
    local ref path
    while read -r ref path; do
        [ -n "${ref}" ] || continue
        install_name_tool -change "${ref}" "@rpath/$(basename "${ref}")" "$1" 2>/dev/null || true
        bundle_dylib "${path}"
    done < <(brew_deps "$1")
}

# $1 = executable already copied into the bundle (Contents/MacOS/...).
bundle_closure() {
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$1" 2>/dev/null || true
    # Dev builds carry Homebrew rpaths; drop them so the bundle never silently falls back to them.
    install_name_tool -delete_rpath "${BREW_PREFIX}/lib" "$1" 2>/dev/null || true
    install_name_tool -delete_rpath "@loader_path/../lib" "$1" 2>/dev/null || true
    relink_deps "$1"
}

# ggml >= 0.23 loads its compute backends (Metal, CPU variants, BLAS) as plugins from
# <ggml>/libexec; the loader also searches the executable's directory, so ship them next to the
# binaries in $1. Whatever the bottle provides gets bundled - no fixed list.
bundle_ggml_plugins() {
    local dir plugin name
    dir="$(brew --prefix ggml 2>/dev/null)/libexec"
    for plugin in "${dir}"/libggml-*.so; do
        [ -f "${plugin}" ] || { echo "[!] No ggml backend plugins in ${dir}" >&2; exit 1; }
        name="$(basename "${plugin}")"
        cp "${plugin}" "$1/${name}"
        chmod u+w "$1/${name}"
        install_name_tool -add_rpath "@loader_path/../Frameworks" "$1/${name}" 2>/dev/null || true
        relink_deps "$1/${name}"
    done
}

# $1 = SwiftPM bin dir, $2 = Contents/MacOS, $3 = Contents/Resources.
# SwiftPM resource bundles (swift-transformers_Hub, swift-crypto_Crypto, mlx-swift_Cmlx, ...) are
# looked up by the generated `Bundle.module` accessor in the app's resourceURL. Without them the
# app works on the dev Mac (the accessor falls back to the absolute .build path compiled in) and
# crashes on every other Mac the first time that module touches its resources.
# The MLX metallib also goes next to the executable, where mlx's load_default_library looks first.
bundle_swiftpm_resources() {
    local bundle metallib
    for bundle in "$1"/*.bundle; do
        [ -d "${bundle}" ] || continue
        ditto "${bundle}" "$3/$(basename "${bundle}")"
    done
    metallib="$1/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
    if [ -f "${metallib}" ]; then
        cp "${metallib}" "$2/mlx.metallib"
        echo "[✓] MLX metallib bundled"
    else
        echo "[i] No MLX metallib in $1 (build with the default swiftbuild system + Metal Toolchain:"
        echo "    xcodebuild -downloadComponent MetalToolchain). The MLX backend reports unavailable."
    fi
}
