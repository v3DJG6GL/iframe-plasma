#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Forgejo release API steps shared by the jobs of .forgejo/workflows/release.yml.
# Needs curl and jq. Environment: TOKEN (API token), REPO (owner/name),
# API (…/api/v1, i.e. $GITHUB_API_URL).
#
#   forgejo-release.sh prepare <tag> <sha> <notes-file>
#       Print the id of the draft release for <tag>, creating it if missing.
#       Prints nothing if a published release already exists: a second run
#       for the same tag never touches a live release.
#   forgejo-release.sh upload <id> <file>...
#       Attach files, replacing same-name assets from an earlier (re-)run.
#   forgejo-release.sh publish <id>
#       Flip the draft live.
#   forgejo-release.sh arch-registry <id> <owner> <group>
#       Push every .pkg.tar.zst attached to release <id> to the owner's Arch
#       package registry under <group>. A version the registry already holds
#       is left as it is (Forgejo answers 409). TOKEN must be a user token
#       with read:repository + write:package: the Actions token counts as
#       anonymous on attachment downloads.
set -euo pipefail

: "${TOKEN:?}" "${REPO:?}" "${API:?}"
hdr="Authorization: token $TOKEN"
rel="$API/repos/$REPO/releases"

die() {
    echo "::error::$*" >&2
    exit 1
}

# The tag lookup endpoint skips drafts, so search the release list (it holds
# drafts too for a token with write access).
find_release() {
    curl -fsS -H "$hdr" "$rel?limit=50" \
        | jq -c --arg t "$1" '[.[] | select(.tag_name == $t)] | first // empty'
}

cmd=${1:-}
shift || true
case "$cmd" in
    prepare)
        tag=$1 sha=$2 notes=$3
        found=$(find_release "$tag")
        if [ -n "$found" ]; then
            if [ "$(jq -r .draft <<<"$found")" != true ]; then
                echo "::notice::release $tag is already published — not uploading again" >&2
                exit 0
            fi
            jq -r .id <<<"$found"
            exit 0
        fi
        body=$(jq -n --arg t "$tag" --arg s "$sha" --rawfile b "$notes" \
            '{tag_name: $t, target_commitish: $s, name: $t, body: $b, draft: true}')
        id=$(curl -fsS -H "$hdr" -H 'Content-Type: application/json' -X POST "$rel" -d "$body" \
            | jq -r '.id // empty')
        [ -n "$id" ] || die "could not create a draft release for $tag"
        echo "$id"
        ;;
    upload)
        id=$1
        shift
        [ "$#" -gt 0 ] || die "no files to upload — refusing to leave an empty release"
        for f in "$@"; do
            name=$(basename "$f")
            curl -fsS -H "$hdr" "$rel/$id/assets" \
                | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' \
                | while read -r aid; do
                    curl -fsS -H "$hdr" -X DELETE "$rel/$id/assets/$aid"
                done
            echo "uploading $name"
            curl -fsS -H "$hdr" -X POST "$rel/$id/assets?name=$name" \
                -F "attachment=@$f" >/dev/null
        done
        ;;
    publish)
        curl -fsS -H "$hdr" -H 'Content-Type: application/json' -X PATCH "$rel/$1" \
            -d '{"draft": false}' >/dev/null
        ;;
    arch-registry)
        id=$1 owner=$2 group=$3
        registry="${API%/api/v1}/api/packages/$owner/arch/$group"
        work=$(mktemp -d)
        assets=$(curl -fsS -H "$hdr" "$rel/$id/assets")
        url_of() { jq -r --arg n "$1" '.[] | select(.name == $n) | .browser_download_url' <<<"$assets"; }
        n=0
        for name in $(jq -r '.[] | select(.name | endswith(".pkg.tar.zst")) | .name' <<<"$assets"); do
            sum=$(url_of "$name.sha256")
            [ -n "$sum" ] || die "release $id has no $name.sha256"
            echo "downloading $name"
            curl -fsS -L -H "$hdr" -o "$work/$name" "$(url_of "$name")"
            curl -fsS -L -H "$hdr" -o "$work/$name.sha256" "$sum"
            (cd "$work" && sha256sum -c "$name.sha256")
            code=$(curl -sS -o "$work/response" -w '%{http_code}' -X PUT -H "$hdr" \
                -H 'Content-Type: application/octet-stream' \
                --data-binary "@$work/$name" "$registry")
            case "$code" in
                201) echo "published $name to $registry" ;;
                409) echo "::notice::$name is already in the registry — left unchanged" ;;
                401 | 403)
                    cat "$work/response" >&2
                    die "HTTP $code from the package registry: PACKAGE_TOKEN must be a token of $owner with write:package"
                    ;;
                *)
                    cat "$work/response" >&2
                    die "HTTP $code while uploading $name to $registry"
                    ;;
            esac
            n=$((n + 1))
        done
        [ "$n" -gt 0 ] || die "release $id has no .pkg.tar.zst asset"
        ;;
    *)
        die "usage: forgejo-release.sh prepare|upload|publish|arch-registry …"
        ;;
esac
