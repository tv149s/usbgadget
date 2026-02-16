#!/usr/bin/env python3
import html
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

CONFIG_PATH = "/etc/default/usb-gadget"
SOURCE_CONFIG_PATH = "/etc/default/usb-gadget-source"
SOURCE_PROFILES_DIR = "/etc/usb-gadget-source.d"
SWITCH_SCRIPT = "/usr/local/bin/usb-gadget-switch-source.sh"
LOCK_PATH = "/etc/default/usb-gadget.uvc-lock"

DEFAULTS = {
    "ENABLE_ACM": "1",
    "ENABLE_HID": "1",
    "ENABLE_HID_MOUSE": "1",
    "ENABLE_UVC": "0",
}

SERVICES = [
    "usb-gadget.service",
    "usb-gadget-stream.service",
    "usb-gadget-source.service",
]


def read_kv(path):
    data = {}
    if not os.path.exists(path):
        return data
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def write_kv(path, values):
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        for key in ["ENABLE_ACM", "ENABLE_HID", "ENABLE_HID_MOUSE", "ENABLE_UVC"]:
            handle.write(f"{key}={values[key]}\n")
    os.replace(tmp_path, path)


def write_kv_generic(path, values):
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")
    os.replace(tmp_path, path)


def run_systemctl(services):
    cmd = ["/bin/systemctl", "restart"] + services
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def read_source_profiles():
    profiles = {}
    if not os.path.isdir(SOURCE_PROFILES_DIR):
        return profiles
    for name in sorted(os.listdir(SOURCE_PROFILES_DIR)):
        if not name.endswith(".conf"):
            continue
        profile_name = name[:-5]
        profile_path = os.path.join(SOURCE_PROFILES_DIR, name)
        profiles[profile_name] = read_kv(profile_path)
    return profiles


def detect_profile(current, profiles):
    if not current or not profiles:
        return ""
    for name, values in profiles.items():
        if not values:
            continue
        match = True
        for key, value in values.items():
            if current.get(key, "") != value:
                match = False
                break
        if match:
            return name
    return ""


def apply_source_profile(profile, profiles):
    if profile not in profiles:
        return 1, "", f"unknown profile: {profile}"

    if os.path.exists(SWITCH_SCRIPT) and os.access(SWITCH_SCRIPT, os.X_OK):
        result = subprocess.run(
            [SWITCH_SCRIPT, profile], capture_output=True, text=True
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()

    try:
        write_kv_generic(SOURCE_CONFIG_PATH, profiles[profile])
    except OSError as exc:
        return 1, "", str(exc)

    return run_systemctl([
        "usb-gadget-stream.service",
        "usb-gadget-source.service",
    ])


def read_udc_state():
    udc_path = "/sys/class/udc/fe980000.usb"
    state = "unknown"
    speed = "unknown"
    if os.path.isdir(udc_path):
        try:
            with open(os.path.join(udc_path, "state"), "r", encoding="utf-8") as handle:
                state = handle.read().strip() or "unknown"
        except OSError:
            pass
        try:
            with open(os.path.join(udc_path, "current_speed"), "r", encoding="utf-8") as handle:
                speed = handle.read().strip() or "unknown"
        except OSError:
            pass
    return state, speed


def read_bound_udc():
    udc_file = "/sys/kernel/config/usb_gadget/pi4g/UDC"
    if not os.path.exists(udc_file):
        return ""
    try:
        with open(udc_file, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def read_functions():
    cfg_path = "/sys/kernel/config/usb_gadget/pi4g/configs/c.1"
    if not os.path.isdir(cfg_path):
        return []
    items = []
    try:
        for name in sorted(os.listdir(cfg_path)):
            if ".usb" in name:
                items.append(name)
    except OSError:
        pass
    return items


def flag(value):
    return "1" if str(value).strip() == "1" else "0"


def html_escape(value):
    return html.escape(value or "")


class GadgetHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query or "")
        msg = params.get("msg", [""])[0]
        err = params.get("err", [""])[0]

        config = DEFAULTS.copy()
        config.update(read_kv(CONFIG_PATH))

        source_config = read_kv(SOURCE_CONFIG_PATH)
        profiles = read_source_profiles()
        current_profile = detect_profile(source_config, profiles)

        udc_state, udc_speed = read_udc_state()
        bound_udc = read_bound_udc()
        functions = read_functions()
        lock_active = os.path.exists(LOCK_PATH)

        body = self.render_page(
            config=config,
            msg=msg,
            err=err,
            udc_state=udc_state,
            udc_speed=udc_speed,
            bound_udc=bound_udc,
            functions=functions,
            lock_active=lock_active,
            profiles=profiles,
            current_profile=current_profile,
        )

        body_bytes = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def do_POST(self):
        if self.path != "/apply":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        form = parse_qs(raw)

        config = DEFAULTS.copy()
        for key in ["ENABLE_ACM", "ENABLE_HID", "ENABLE_HID_MOUSE", "ENABLE_UVC"]:
            config[key] = flag(form.get(key, ["0"])[0])

        if config["ENABLE_UVC"] == "0" and os.path.exists(LOCK_PATH):
            self.redirect("/" + "?err=" + "UVC%20lock%20is%20enabled")
            return

        source_profiles = read_source_profiles()
        selected_profile = form.get("SOURCE_PROFILE", [""])[0].strip()
        if selected_profile:
          code, out, err = apply_source_profile(selected_profile, source_profiles)
          if code != 0:
            message = "source switch failed"
            if err:
              message += ": " + err
            elif out:
              message += ": " + out
            self.redirect("/" + "?err=" + html_escape(message))
            return

        try:
          write_kv(CONFIG_PATH, config)
        except OSError as exc:
          self.redirect("/" + "?err=" + html_escape(str(exc)))
          return

        code, out, err = run_systemctl(["usb-gadget.service", "usb-gadget-stream.service"])
        if code != 0:
            message = "restart failed"
            if err:
                message += ": " + err
            elif out:
                message += ": " + out
            self.redirect("/" + "?err=" + html_escape(message))
            return

        self.redirect("/" + "?msg=" + "applied")

    def redirect(self, target):
        self.send_response(303)
        self.send_header("Location", target)
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[usb-gadget-webui] " + fmt % args + "\n")

    def render_page(
        self,
        config,
        msg,
        err,
        udc_state,
        udc_speed,
        bound_udc,
        functions,
        lock_active,
        profiles,
        current_profile,
    ):
        def checked(key):
            return "checked" if config.get(key, "0") == "1" else ""

        status_line = ""
        if msg:
            status_line = f"<div class=\"banner ok\">{html_escape(msg)}</div>"
        if err:
            status_line = f"<div class=\"banner err\">{html_escape(err)}</div>"

        lock_note = ""
        if lock_active:
            lock_note = "<div class=\"note warn\">UVC lock is enabled. Disable with sudo gadget-mode unlock.</div>"

        functions_html = ", ".join(html_escape(item) for item in functions) or "none"
        def selected(name):
            return "selected" if name == current_profile else ""

        profile_options = "".join(
            f"<option value=\"{html_escape(name)}\" {selected(name)}>{html_escape(name)}</option>"
            for name in profiles.keys()
        ) or "<option value=\"\" disabled>no profiles found</option>"

        return f"""<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
    <title>USB Gadget Control</title>
    <style>
      :root {{
        --bg1: #0b0c10;
        --bg2: #1b1d24;
        --ink: #e9e8e5;
        --muted: #a1a7b3;
        --accent: #f6c453;
        --accent-2: #84d2c5;
        --card: rgba(255, 255, 255, 0.08);
        --border: rgba(255, 255, 255, 0.15);
        --shadow: rgba(0, 0, 0, 0.35);
      }}

      * {{ box-sizing: border-box; }}
      body {{
        margin: 0;
        font-family: "IBM Plex Sans", "Source Sans 3", "Noto Sans", "DejaVu Sans", sans-serif;
        color: var(--ink);
        background: radial-gradient(1200px 600px at 15% -10%, rgba(246, 196, 83, 0.25), transparent 70%),
                    radial-gradient(900px 500px at 90% 10%, rgba(132, 210, 197, 0.22), transparent 70%),
                    linear-gradient(145deg, var(--bg1), var(--bg2));
        min-height: 100vh;
      }}

      .wrap {{
        max-width: 980px;
        margin: 0 auto;
        padding: 40px 20px 60px;
      }}

      header {{
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin-bottom: 28px;
      }}

      h1 {{
        font-size: 34px;
        margin: 0;
        letter-spacing: 0.02em;
      }}

      .sub {{
        color: var(--muted);
        font-size: 15px;
      }}

      .grid {{
        display: grid;
        gap: 18px;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      }}

      .card {{
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 18px;
        padding: 18px;
        box-shadow: 0 18px 40px var(--shadow);
        backdrop-filter: blur(8px);
        animation: lift 0.6s ease both;
      }}

      .card:nth-child(2) {{ animation-delay: 0.05s; }}
      .card:nth-child(3) {{ animation-delay: 0.1s; }}

      @keyframes lift {{
        from {{ transform: translateY(12px); opacity: 0; }}
        to {{ transform: translateY(0); opacity: 1; }}
      }}

      .row {{
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        margin: 12px 0;
      }}

      .toggle {{
        display: flex;
        align-items: center;
        gap: 10px;
      }}

      .toggle input {{
        width: 18px;
        height: 18px;
      }}

      .pill {{
        font-size: 12px;
        padding: 4px 10px;
        border-radius: 999px;
        border: 1px solid var(--border);
        color: var(--muted);
      }}

      .meta {{
        font-size: 13px;
        color: var(--muted);
        line-height: 1.5;
      }}

      .banner {{
        padding: 10px 14px;
        border-radius: 12px;
        margin: 0 0 16px;
        font-size: 14px;
      }}

      .banner.ok {{
        background: rgba(132, 210, 197, 0.25);
        border: 1px solid rgba(132, 210, 197, 0.5);
      }}

      .banner.err {{
        background: rgba(255, 129, 109, 0.22);
        border: 1px solid rgba(255, 129, 109, 0.5);
      }}

      .note {{
        margin-top: 12px;
        padding: 10px 12px;
        border-radius: 12px;
        font-size: 13px;
      }}

      .note.warn {{
        background: rgba(246, 196, 83, 0.18);
        border: 1px solid rgba(246, 196, 83, 0.4);
      }}

      button {{
        background: var(--accent);
        color: #1a1a1a;
        border: none;
        padding: 12px 18px;
        border-radius: 12px;
        font-weight: 700;
        letter-spacing: 0.02em;
        cursor: pointer;
        box-shadow: 0 12px 30px rgba(246, 196, 83, 0.25);
      }}

      .footer {{
        margin-top: 20px;
        color: var(--muted);
        font-size: 12px;
      }}

      @media (max-width: 640px) {{
        h1 {{ font-size: 28px; }}
        .wrap {{ padding: 30px 16px 50px; }}
      }}
    </style>
  </head>
  <body>
    <div class=\"wrap\">
      <header>
        <h1>USB Gadget Control</h1>
        <div class=\"sub\">Toggle serial, HID, and UVC functions. Changes apply immediately.</div>
      </header>
      {status_line}
      <form method=\"post\" action=\"/apply\" class=\"grid\">
        <div class=\"card\">
          <div class=\"row\">
            <strong>Device Functions</strong>
            <span class=\"pill\">live config</span>
          </div>
          <label class=\"toggle\"><input type=\"checkbox\" name=\"ENABLE_ACM\" value=\"1\" {checked("ENABLE_ACM")}/>Serial (ACM)</label>
          <label class=\"toggle\"><input type=\"checkbox\" name=\"ENABLE_HID\" value=\"1\" {checked("ENABLE_HID")}/>HID Keyboard</label>
          <label class=\"toggle\"><input type=\"checkbox\" name=\"ENABLE_HID_MOUSE\" value=\"1\" {checked("ENABLE_HID_MOUSE")}/>HID Mouse</label>
          <label class=\"toggle\"><input type=\"checkbox\" name=\"ENABLE_UVC\" value=\"1\" {checked("ENABLE_UVC")}/>UVC Camera</label>
          <div class=\"note warn\">Enabling UVC triggers USB re-enumeration on the host.</div>
          {lock_note}
          <div class=\"row\" style=\"margin-top: 16px;\">
            <button type=\"submit\">Apply Changes</button>
          </div>
        </div>
        <div class=\"card\">
          <div class=\"row\"><strong>UDC Status</strong></div>
          <div class=\"meta\">Bound UDC: {html_escape(bound_udc) or "none"}</div>
          <div class=\"meta\">UDC state: {html_escape(udc_state)}</div>
          <div class=\"meta\">UDC speed: {html_escape(udc_speed)}</div>
          <div class=\"meta\">Active functions: {functions_html}</div>
        </div>
        <div class=\"card\">
          <div class=\"row\"><strong>Video Source</strong></div>
          <div class=\"meta\">Select the active UVC source profile.</div>
          <div class=\"row\">
            <select name=\"SOURCE_PROFILE\" style=\"flex: 1; padding: 10px; border-radius: 10px; border: 1px solid var(--border); background: transparent; color: var(--ink);\">
              {profile_options}
            </select>
          </div>
          <div class=\"meta\">Profiles live in {html_escape(SOURCE_PROFILES_DIR)}.</div>
        </div>
        <div class=\"card\">
          <div class=\"row\"><strong>Notes</strong></div>
          <div class=\"meta\">Config file: {html_escape(CONFIG_PATH)}</div>
          <div class=\"meta\">Source config: {html_escape(SOURCE_CONFIG_PATH)}</div>
          <div class=\"meta\">Services: usb-gadget + stream + source</div>
          <div class=\"meta\">If devices disappear, replug on the host or reboot.</div>
        </div>
      </form>
      <div class=\"footer\">USB Gadget Web UI</div>
    </div>
  </body>
</html>"""


def main():
    listen_addr = os.environ.get("GADGET_WEBUI_ADDR", "0.0.0.0")
    listen_port = int(os.environ.get("GADGET_WEBUI_PORT", "8765"))

    server = HTTPServer((listen_addr, listen_port), GadgetHandler)
    sys.stderr.write(
        f"[usb-gadget-webui] listening on http://{listen_addr}:{listen_port}\n"
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
