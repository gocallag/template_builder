import socket
import time
import re
import argparse

# Standard Packer tokens → QEMU key names
KEYMAP = {
    "<enter>": "ret", "<tab>": "tab", "<esc>": "esc",
    "<bs>": "backspace", "<backspace>": "backspace", "<bksp>": "backspace", "<del>": "delete",
    "<up>": "up", "<down>": "down", "<left>": "left", "<right>": "right",
    "<home>": "home", "<end>": "end", "<pgup>": "pageup", "<pgdn>": "pagedown",
    "<f1>": "f1", "<f2>": "f2", "<f3>": "f3", "<f4>": "f4",
    "<f5>": "f5", "<f6>": "f6", "<f7>": "f7", "<f8>": "f8",
    "<f9>": "f9", "<f10>": "f10", "<f11>": "f11", "<f12>": "f12",
    # Numeric keypad
    "<kp0>": "kp0", "<kp1>": "kp1", "<kp2>": "kp2", "<kp3>": "kp3",
    "<kp4>": "kp4", "<kp5>": "kp5", "<kp6>": "kp6", "<kp7>": "kp7",
    "<kp8>": "kp8", "<kp9>": "kp9",
    "<kpadd>": "kpadd", "<kpsubtract>": "kpsubtract",
    "<kpmultiply>": "kpmultiply", "<kpdivide>": "kpdivide",
    "<kpenter>": "kpenter", "<kpdecimal>": "kpdecimal",
}

# Modifier press/release tokens
MODIFIER_TOKENS = {
    "<leftCtrlOn>": ("ctrl", True), "<leftCtrlOff>": ("ctrl", False),
    "<rightCtrlOn>": ("ctrl", True), "<rightCtrlOff>": ("ctrl", False),
    "<leftAltOn>": ("alt", True), "<leftAltOff>": ("alt", False),
    "<rightAltOn>": ("alt", True), "<rightAltOff>": ("alt", False),
    "<leftShiftOn>": ("shift", True), "<leftShiftOff>": ("shift", False),
    "<rightShiftOn>": ("shift", True), "<rightShiftOff>": ("shift", False),
}

# Base punctuation → QEMU key names (unshifted)
PUNCTUATION_MAP = {
    " ": "spc", ".": "dot", "/": "slash", "-": "minus", "_": "underscore",
    "=": "equal", "+": "plus", ",": "comma", ";": "semicolon", "'": "apostrophe", "\"": "quotedbl",
    "@": "at", "#": "numbersign", "$": "dollar", "%": "percent",
    "^": "caret", "&": "ampersand", "*": "asterisk", "(": "parenleft", ")": "parenright",
    "[": "bracketleft", "]": "bracketright", "{": "braceleft", "}": "braceright",
    "<": "less", ">": "greater", "\\": "backslash", "|": "bar", "`": "grave", "~": "tilde",
    "!": "exclam", "?": "question", ":": "colon",
}

# Shifted symbols → QEMU combined names (preferred when generating exact shifted forms)
SHIFTED_SYMBOLS = {
    "!": "shift-1", "@": "shift-2", "#": "shift-3", "$": "shift-4",
    "%": "shift-5", "^": "shift-6", "&": "shift-7", "*": "shift-8",
    "(": "shift-9", ")": "shift-0",
    "_": "shift-minus", "+": "shift-equal",
    "{": "shift-bracketleft", "}": "shift-bracketright",
    "|": "shift-backslash", ":": "shift-semicolon",
    "\"": "shift-apostrophe", "<": "shift-comma",
    ">": "shift-dot", "?": "shift-slash", "~": "shift-grave",
}

# Deterministic modifier ordering for combined names
MOD_ORDER = ("shift", "ctrl", "alt")

def combine_with_modifiers(base_key: str, mods: set) -> str:
    """
    Combine held modifiers with a base key into QEMU's combined name.
    Example: mods={'ctrl','alt'} and base_key='f2' => 'ctrl-alt-f2'
             mods={'shift'} and base_key='a' => 'shift-a'
    """
    if not mods:
        return base_key
    parts = []
    for m in MOD_ORDER:
        if m in mods:
            parts.append(m)
    parts.append(base_key)
    return "-".join(parts)

def parse_boot_command(cmd: str):
    """
    Parse a Packer-style boot_command string into actions with correct combined sendkeys.
    Maintains a held modifier state that affects subsequent keys until released.
    Returns a list of tuples: (action, value, original)
    """
    result = []
    i = 0
    held_mods = set()

    while i < len(cmd):
        if cmd[i] == "<":
            j = cmd.find(">", i)
            if j == -1:
                raise ValueError(f"Unclosed token starting at position {i}")
            token = cmd[i:j+1]
            lower = token.lower()

            # Wait handling: <wait> or <waitN>
            if lower.startswith("<wait"):
                m = re.match(r"<wait(\d+)>", lower)
                seconds = int(m.group(1)) if m else 1
                result.append(("wait", seconds, token))
                i = j + 1
                continue

            # Modifier toggle
            if token in MODIFIER_TOKENS:
                mod_name, turn_on = MODIFIER_TOKENS[token]
                if turn_on:
                    held_mods.add(mod_name)
                else:
                    held_mods.discard(mod_name)
                result.append(("modifier", f"{mod_name}-{'on' if turn_on else 'off'}", token))
                i = j + 1
                continue

            # Standard mapped token (function keys, navigation, keypad)
            if token in KEYMAP:
                base = KEYMAP[token]
                combined = combine_with_modifiers(base, held_mods)
                result.append(("sendkey", combined, token))
                i = j + 1
                continue

            # Unknown token: log a warning and skip it rather than raising
            print(f"[WARN] Unsupported token: {token} — skipping")
            i = j + 1
            continue

        # Literal character
        ch = cmd[i]

        # Uppercase letters → prefer combined 'shift-<lower>' unless Shift is already held
        if ch.isupper():
            base = ch.lower()
            combined = combine_with_modifiers(base, held_mods | {"shift"})
            result.append(("sendkey", combined, ch))
            i += 1
            continue

        # Lowercase letters and digits → combine with held modifiers if any
        if ch.islower() or ch.isdigit():
            base = ch
            combined = combine_with_modifiers(base, held_mods)
            result.append(("sendkey", combined, ch))
            i += 1
            continue

        # Shifted symbols: prefer exact 'shift-<key>' forms
        if ch in SHIFTED_SYMBOLS:
            # If Shift is already held, we can send the underlying base key with held shift.
            # But using the explicit shifted form is more deterministic.
            explicit = SHIFTED_SYMBOLS[ch]
            # If other modifiers are held (e.g., ctrl), combine them with the shifted base:
            # explicit is like 'shift-1' -> split to base '1' and ensure shift in mods
            if explicit.startswith("shift-"):
                base = explicit[len("shift-"):]
                combined = combine_with_modifiers(base, held_mods | {"shift"})
            else:
                combined = combine_with_modifiers(explicit, held_mods)
            result.append(("sendkey", combined, ch))
            i += 1
            continue

        # Unshifted punctuation and whitespace
        if ch in PUNCTUATION_MAP:
            base = PUNCTUATION_MAP[ch]
            combined = combine_with_modifiers(base, held_mods)
            result.append(("sendkey", combined, ch))
            i += 1
            continue

        # Unknown character: log a warning and skip it rather than raising
        print(f"[WARN] Unsupported character: {ch} — skipping")
        i += 1
        continue

    return result

def send_to_qemu(commands, host="localhost", port=4447, unix_socket=None, key_interval=0.05):
    """
    Send parsed commands to QEMU monitor (TCP or UNIX socket).
    Logs both original input and the final QEMU sendkey string.
    """
    if unix_socket:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(unix_socket)
    else:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect((host, port))

    for action, value, original in commands:
        if action == "wait":
            print(f"[WAIT] {original} → {value} seconds")
            time.sleep(value)
        elif action == "sendkey":
            print(f"[SENDKEY] {original} → {value}")
            s.sendall(f"sendkey {value}\n".encode())
            time.sleep(key_interval)
        elif action == "modifier":
            # Modifier toggles are logged for audit, but QEMU sendkey expects combined names,
            # so we do NOT send 'ctrl-on'/'shift-off' to QEMU. They are state changes only.
            print(f"[MODIFIER] {original} → {value}")
            # No sendkey for modifier toggles themselves.
        else:
            raise ValueError(f"Unknown action: {action}")

    s.close()

def main():
    parser = argparse.ArgumentParser(description="Send Packer-style boot_command to QEMU monitor with correct combined keys")
    parser.add_argument("--host", default="localhost", help="QEMU monitor host")
    parser.add_argument("--port", type=int, default=4447, help="QEMU monitor TCP port")
    parser.add_argument("--unix-socket", help="QEMU monitor UNIX socket path")
    parser.add_argument("--boot-command", required=True, help="Packer-style boot_command string")
    parser.add_argument("--key-interval", type=float, default=0.05, help="Delay between keystrokes in seconds")
    args = parser.parse_args()

    commands = parse_boot_command(args.boot_command)
    send_to_qemu(commands, host=args.host, port=args.port, unix_socket=args.unix_socket, key_interval=args.key_interval)

if __name__ == "__main__":
    main()