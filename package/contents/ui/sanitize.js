/*
 * SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Shared Unicode bidi/format/C0+C1 control-char strip helper.
 *
 * Used by every site that renders attacker-influenced strings in chrome
 * (host chips, status-overlay error messages, autheliaHost field):
 *
 *   - CyberToolbar.qml host chip — Chromium host strings can carry an
 *     embedded U+202E (RLO) that re-orders the trust copy on screen.
 *   - StatusOverlay.qml error message — errorString is partly composed
 *     from network/server data (proxy 502 bodies, cert-mismatch host
 *     names) and a hostile origin can smuggle bidi controls.
 *   - ConfigAuth.qml autheliaHost — silent bypass of the WebTab overlay
 *     host comparison ("authelia.example.com" vs "authelia.example.com​").
 *
 *   200B..200D ZWSP/ZWNJ/ZWJ          200E..200F LRM/RLM     061C ALM
 *   202A..202E PDF/LRE/RLE/LRO/RLO    2066..2069 LRI/RLI/FSI/PDI
 *   2028..2029 LS/PS                  FEFF BOM/ZWNBSP
 *   0000..001F C0  +  007F DEL  +  0080..009F C1
 *
 * U+2028 (LS) and U+2029 (PS) are ECMAScript LineTerminators that
 * cannot appear inside a /.../ regex literal, so build from a String
 * and feed to RegExp().
 */
.pragma library

var stripRe = new RegExp(
    "[\\u0000-\\u001F\\u007F-\\u009F"
  + "\\u061C\\u200B-\\u200F"
  + "\\u202A-\\u202E\\u2066-\\u2069"
  + "\\u2028\\u2029\\uFEFF]", "g");

function strip(s) {
    return String(s || "").replace(stripRe, "");
}
