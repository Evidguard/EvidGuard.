#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SpyGuard Control Panel - v2.2.1 (Hotfix Debian 13 / polkit)
Correcciones:
  - check_root(): pasa DISPLAY/WAYLAND/DBUS vars a pkexec/sudo vía 'env'
  - open_url():   pasa vars de entorno gráfico al sudo -u USER xdg-open
  - _notify():    ejecuta notify-send como el usuario de sesión con vars correctas
  - Eliminado sudo -A (requería SUDO_ASKPASS no estándar)
"""

import os, sys, traceback

_LOG_FILE = "/tmp/spyguard-control-panel.log"

def _log_crash(msg):
    with open(_LOG_FILE, "a") as f:
        f.write(f"[{__import__('time').strftime('%H:%M:%S')}] {msg}\n")

try:
    import tkinter as tk
    from tkinter import ttk, font, messagebox
    import subprocess, threading, time, shutil, math, socket

    # === DETECTAR RUTAS DE INSTALACIÓN ===
    _SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    _INSTALL_DIR = os.path.abspath(os.path.join(_SCRIPT_DIR, ".."))

    # === CONFIGURACION ===
    SERVICES = ["spyguard-backend", "spyguard-frontend", "spyguard-watchers"]
    BACKEND_URL  = "https://localhost:8443"
    FRONTEND_URL = "http://localhost:8000"
    CERT_SRC = "/usr/share/spyguard/certs/"
    CERT_DST = "/usr/share/spyguard/server/backend/"
    def _resolve_gui_user():
        # sudo pone SUDO_USER; pkexec pone PKEXEC_UID (no SUDO_USER)
        sudo_user = os.environ.get("SUDO_USER", "")
        if sudo_user and sudo_user != "root":
            return sudo_user
        pkexec_uid = os.environ.get("PKEXEC_UID", "")
        if pkexec_uid:
            try:
                import pwd
                return pwd.getpwuid(int(pkexec_uid)).pw_name
            except Exception:
                pass
        user = os.environ.get("USER", "")
        if user and user != "root":
            return user
        # Último fallback: primer usuario humano con UID >= 1000
        try:
            import pwd
            for entry in pwd.getpwall():
                if entry.pw_uid >= 1000 and entry.pw_shell not in ("/usr/sbin/nologin", "/bin/false"):
                    return entry.pw_name
        except Exception:
            pass
        return "pi"
    GUI_USER = _resolve_gui_user()

    LOGO_PATHS = [
        os.path.join(_INSTALL_DIR, "assets", "logo.png"),
        "/usr/share/pixmaps/spyguard-cp.png",
        "/usr/share/pixmaps/spyguard.png",
        "/usr/share/spyguard/logo.png",
        "/opt/spyguard/logo.png",
        "/usr/local/bin/logo.png",
    ]

    # === PALETA ===
    BG          = "#0a0a0a"
    BG_CARD     = "#111111"
    FG          = "#f0f0f0"
    FG_DIM      = "#666666"
    FG_FAINT    = "#333333"
    BORDER      = "#1e1e1e"
    CONSOLE_BG  = "#080808"
    CONSOLE_FG  = "#a0a0a0"
    STATUS_OK   = "#22c55e"
    STATUS_WARN = "#f59e0b"
    STATUS_ERR  = "#ef4444"
    STATUS_IDLE = "#374151"
    BTN_BG    = "#f0f0f0"
    BTN_FG    = "#0a0a0a"
    BTN_HOVER = "#d4d4d4"
    BTN2_BG    = "#1a1a1a"
    BTN2_FG    = "#f0f0f0"
    BTN2_HOVER = "#252525"
    SCROLL_BG = "#0f0f0f"
    SCROLL_FG = "#1c1c1c"
    PULSE_SPEED = 5.0

    # === HELPER: variables de entorno gráfico para subprocesos elevados ===
    def _gui_env_pairs():
        """Devuelve lista de 'VAR=val' con las vars de display/sesión actuales."""
        pairs = []
        for var in ("DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR",
                    "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE",
                    "XDG_SESSION_DESKTOP", "GDK_BACKEND"):
            val = os.environ.get(var, "")
            if val:
                pairs.append(f"{var}={val}")
        # Fallback si no hay display detectado
        if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
            pairs.append("DISPLAY=:0")
        return pairs

    class PulsingLED:
        def __init__(self, parent, size=14, bg=BG_CARD):
            self.size = size; self.bg = bg; self.color = STATUS_IDLE
            self._pulsing = False; self._anim_id = None
            self.canvas = tk.Canvas(parent, width=size, height=size, bg=bg, highlightthickness=0)
            self._draw()

        def _draw(self):
            self.canvas.delete("all")
            s = self.size; cx = s//2; cy = s//2; r = s//2 - 2
            if self._pulsing:
                t = time.time()
                pulse = 0.5 + 0.5 * math.sin(t * PULSE_SPEED)
                gr1 = r + 10 + 3 * pulse
                a1 = 0.08 + 0.18 * pulse
                self.canvas.create_oval(cx-gr1, cy-gr1, cx+gr1, cy+gr1,
                    fill=self._blend(self.color, self.bg, a1), outline="")
                gr2 = r + 5 + 2 * pulse
                a2 = 0.20 + 0.40 * pulse
                self.canvas.create_oval(cx-gr2, cy-gr2, cx+gr2, cy+gr2,
                    fill=self._blend(self.color, self.bg, a2), outline="")
                center_color = self._lighten(self.color, 0.30 * pulse)
            else:
                center_color = self.color
            self.canvas.create_oval(cx-r, cy-r, cx+r, cy+r, fill=center_color, outline="")
            hr = max(2, r//3)
            if self._pulsing:
                highlight = self._lighten(center_color, 0.50 + 0.20 * pulse)
            else:
                highlight = self._lighten(self.color, 0.40) if self.color != STATUS_IDLE else self.bg
            offset = max(1, r//5)
            self.canvas.create_oval(cx-hr+offset, cy-hr-offset, cx+hr-offset, cy+hr-offset,
                fill=highlight, outline="")

        def _lighten(self, hex_color, amount):
            try:
                c = hex_color.lstrip("#")
                r,g,b = int(c[0:2],16), int(c[2:4],16), int(c[4:6],16)
                return "#{:02x}{:02x}{:02x}".format(
                    min(255,int(r+(255-r)*amount)), min(255,int(g+(255-g)*amount)), min(255,int(b+(255-b)*amount)))
            except: return hex_color

        def _blend(self, fg, bg, alpha):
            try:
                fc=fg.lstrip("#"); bc=bg.lstrip("#")
                fr,fg2,fb=int(fc[0:2],16),int(fc[2:4],16),int(fc[4:6],16)
                br,bg2,bb=int(bc[0:2],16),int(bc[2:4],16),int(bc[4:6],16)
                return "#{:02x}{:02x}{:02x}".format(
                    int(fr*alpha+br*(1-alpha)), int(fg2*alpha+bg2*(1-alpha)), int(fb*alpha+bb*(1-alpha)))
            except: return fg

        def set_state(self, color, pulsing=False):
            was = self._pulsing; self.color=color; self._pulsing=pulsing; self._draw()
            if pulsing and not was: self._animate()
            elif not pulsing and was and self._anim_id:
                try: self.canvas.after_cancel(self._anim_id)
                except: pass
                self._anim_id=None

        def _animate(self):
            if not self._pulsing: return
            self._draw(); self._anim_id = self.canvas.after(50, self._animate)

    class Tooltip:
        def __init__(self, widget, text):
            self.widget=widget; self.text=text; self.tip=None
            widget.bind("<Enter>", self._show); widget.bind("<Leave>", self._hide)
        def _show(self,_):
            x=self.widget.winfo_rootx()+20; y=self.widget.winfo_rooty()+self.widget.winfo_height()+4
            self.tip=tk.Toplevel(self.widget); self.tip.wm_overrideredirect(True); self.tip.wm_geometry(f"+{x}+{y}")
            tk.Label(self.tip, text=self.text, font=("Helvetica",8), bg="#1e1e1e", fg="#cccccc", padx=8, pady=4, bd=0, relief="flat").pack()
        def _hide(self,_):
            if self.tip:
                try: self.tip.destroy()
                except: pass
                self.tip=None

    class SpyGuardLogo:
        @staticmethod
        def draw(parent, size=40, bg=BG):
            c=tk.Canvas(parent, width=size, height=size, bg=bg, highlightthickness=0)
            cx,cy=size//2,size//2; r=size//2-3
            pts=[]
            for i in range(6):
                a=math.radians(60*i-90)
                pts.extend([cx+r*math.cos(a), cy+r*math.sin(a)])
            c.create_polygon(pts, fill="#f0f0f0", outline="", smooth=True)
            er=r*0.42
            c.create_oval(cx-er,cy-er,cx+er,cy+er, fill="#0a0a0a", outline="")
            ir=er*0.55
            c.create_oval(cx-ir,cy-ir,cx+ir,cy+ir, fill="#f0f0f0", outline="")
            pr=ir*0.45
            c.create_oval(cx-pr,cy-pr,cx+pr,cy+pr, fill="#0a0a0a", outline="")
            c.create_oval(cx+pr*0.2, cy-pr*0.7, cx+pr*0.7, cy-pr*0.2, fill="#f0f0f0", outline="")
            return c

    class SpyGuardGUI:
        def __init__(self, root):
            self.root=root; self.root.title("SpyGuard Control Panel")
            self.root.geometry("820x680"); self.root.configure(bg=BG); self.root.minsize(700,560)
            self.f_subtitle=font.Font(family="Helvetica", size=10)
            self.f_mono=font.Font(family="DejaVu Sans Mono", size=8)
            self.f_small=font.Font(family="Helvetica", size=9)
            self.f_btn=font.Font(family="Helvetica", size=9, weight="bold")
            self.f_tiny=font.Font(family="Helvetica", size=8)
            self.f_label=font.Font(family="Helvetica", size=7, weight="bold")
            self.f_svc=font.Font(family="Helvetica", size=10, weight="bold")
            self._uptime={s:0 for s in SERVICES}
            self._uptime_active={s:False for s in SERVICES}
            self._build_ui(); self.check_status(); self.auto_refresh(); self._tick_uptime()

        def _build_ui(self):
            sty=ttk.Style()
            try: sty.theme_use("clam")
            except: pass
            main=tk.Frame(self.root, bg=BG); main.pack(fill="both", expand=True, padx=28, pady=22)

            hdr=tk.Frame(main, bg=BG); hdr.pack(fill="x", pady=(0,20))
            logo_loaded=False
            for path in LOGO_PATHS:
                if os.path.exists(path):
                    try:
                        img=tk.PhotoImage(file=path); h=img.height()
                        if h>48:
                            factor=max(1,round(h/48)); img=img.subsample(factor,factor)
                        lbl=tk.Label(hdr, image=img, bg=BG); lbl.image=img; lbl.pack(side="left", padx=(0,14))
                        logo_loaded=True; break
                    except: continue
            if not logo_loaded:
                SpyGuardLogo.draw(hdr, size=40, bg=BG).pack(side="left", padx=(0,14))
            tf=tk.Frame(hdr, bg=BG); tf.pack(side="left", fill="y")

            rf=tk.Frame(hdr, bg=BG); rf.pack(side="right", anchor="ne")
            self.clock_label=tk.Label(rf, text="", font=self.f_tiny, bg=BG, fg=FG); self.clock_label.pack(anchor="e")
            tk.Label(rf, text=f"user: {GUI_USER}", font=self.f_tiny, bg=BG, fg=FG).pack(anchor="e")
            self._update_clock()

            tk.Frame(main, bg=BORDER, height=1).pack(fill="x", pady=(0,18))

            sc=tk.Frame(main, bg=BG_CARD, highlightbackground=BORDER, highlightthickness=1, bd=0)
            sc.pack(fill="x", pady=(0,18), ipady=14)
            self.status_led=PulsingLED(sc, size=18, bg=BG_CARD); self.status_led.canvas.pack(side="left", padx=(18,12))
            stf=tk.Frame(sc, bg=BG_CARD); stf.pack(side="left", fill="both", expand=True)
            stf_inner=tk.Frame(stf, bg=BG_CARD); stf_inner.pack(expand=True, anchor="w")
            self.status_text=tk.Label(stf_inner, text="Verificando...", font=("Helvetica",11,"bold"), bg=BG_CARD, fg=FG); self.status_text.pack(anchor="w")
            self.status_detail=tk.Label(stf_inner, text="", font=self.f_small, bg=BG_CARD, fg=FG_DIM); self.status_detail.pack(anchor="w")
            self.global_up=tk.Label(sc, text="", font=self.f_tiny, bg=BG_CARD, fg=FG_FAINT); self.global_up.pack(side="right", padx=20)

            self._sec_label(main, "SERVICIOS")
            sf=tk.Frame(main, bg=BG); sf.pack(fill="x", pady=(0,18))
            for i in range(len(SERVICES)): sf.columnconfigure(i, weight=1)
            self.service_cards={}
            for i,svc in enumerate(SERVICES): self._build_card(sf, svc, i)

            self._sec_label(main, "ACCIONES")
            bf=tk.Frame(main, bg=BG); bf.pack(fill="x", pady=(0,14))
            btn_specs=[
                ("Iniciar Todo", self.start_all, BTN_BG, BTN_FG, BTN_HOVER),
                ("Detener Todo", self.stop_all, BTN2_BG, BTN2_FG, BTN2_HOVER),
                ("Abrir Frontend", lambda: self.open_url(FRONTEND_URL), BTN2_BG, BTN2_FG, BTN2_HOVER),
                ("Abrir Backend", lambda: self.open_url(BACKEND_URL), BTN2_BG, BTN2_FG, BTN2_HOVER),
            ]
            self.buttons=[]
            for txt,cmd,bg_,fg_,hov in btn_specs:
                b=tk.Button(bf, text=txt, font=self.f_btn, bg=bg_, fg=fg_, activebackground=hov, activeforeground=fg_, bd=0, cursor="hand2", padx=14, pady=10, command=cmd, relief="flat")
                b.pack(side="left", expand=True, fill="x", padx=3)
                b.bind("<Enter>", lambda e,w=b,h=hov: w.config(bg=h))
                b.bind("<Leave>", lambda e,w=b,o=bg_: w.config(bg=o))
                self.buttons.append(b)

            self.progress_var=tk.DoubleVar(value=0)
            sty.configure("Slim.Horizontal.TProgressbar", troughcolor=BG_CARD, background="#444444", darkcolor="#444444", lightcolor="#444444", bordercolor=BG, thickness=3)
            ttk.Progressbar(main, variable=self.progress_var, mode="determinate", maximum=100, style="Slim.Horizontal.TProgressbar").pack(fill="x", pady=(0,12))

            lh=tk.Frame(main, bg=BG); lh.pack(fill="x", pady=(0,4))
            self._sec_label_inline(lh, "SYSTEM LOGS")
            clr=tk.Label(lh, text="limpiar", font=self.f_tiny, bg=BG, fg=FG_FAINT, cursor="hand2"); clr.pack(side="right")
            clr.bind("<Button-1>", lambda e: self._clear_logs())
            clr.bind("<Enter>", lambda e: clr.config(fg=FG))
            clr.bind("<Leave>", lambda e: clr.config(fg=FG_FAINT))

            cf=tk.Frame(main, bg=BG_CARD, highlightbackground=BORDER, highlightthickness=1); cf.pack(fill="both", expand=True)
            self.console=tk.Text(cf, height=10, bg=CONSOLE_BG, fg=CONSOLE_FG, insertbackground=FG, font=self.f_mono, bd=0, wrap=tk.WORD, padx=12, pady=10, state="disabled", selectbackground="#2a2a2a", selectforeground=FG)
            self.console.pack(side="left", fill="both", expand=True)

            sty.configure("Ghost.Vertical.TScrollbar", background=SCROLL_FG, troughcolor=SCROLL_BG, bordercolor=SCROLL_BG, arrowcolor=SCROLL_BG, width=4, relief="flat", borderwidth=0)
            sty.map("Ghost.Vertical.TScrollbar", background=[("active","#2a2a2a"),("pressed","#333333")], troughcolor=[("active",SCROLL_BG)])
            try:
                sty.layout("Ghost.Vertical.TScrollbar", [("Vertical.Scrollbar.trough", {"children":[("Vertical.Scrollbar.thumb",{"expand":"1","sticky":"nswe"})],"sticky":"ns"})])
            except: pass
            sb=ttk.Scrollbar(cf, orient="vertical", command=self.console.yview, style="Ghost.Vertical.TScrollbar"); sb.pack(side="right", fill="y")
            self.console.config(yscrollcommand=sb.set)

            self.console.tag_config("ts", foreground="#2a2a2a")
            self.console.tag_config("ok", foreground=STATUS_OK)
            self.console.tag_config("err", foreground=STATUS_ERR)
            self.console.tag_config("warn", foreground=STATUS_WARN)
            self.console.tag_config("info", foreground="#686868")
            self.console.tag_config("cmd", foreground="#3a3a3a")
            self.console.tag_config("sep", foreground="#1e1e1e")

            ft=tk.Frame(main, bg=BG); ft.pack(fill="x", pady=(10,0))
            tk.Label(ft, text="Ctrl+Q Salir  •  F5 Refrescar  •  Auto-refresh 5s", font=self.f_tiny, bg=BG, fg=FG).pack(side="left")
            tk.Label(ft, text="v2.2.1", font=self.f_tiny, bg=BG, fg=FG_FAINT).pack(side="right")

            self.root.bind("<Control-q>", lambda e: self.on_close())
            self.root.bind("<F5>", lambda e: self.check_status())
            self.root.protocol("WM_DELETE_WINDOW", self.on_close)
            self.log("SpyGuard Control Panel v2.2.1 iniciado", "info")
            self.log(f"Usuario: {GUI_USER}", "info")

        def _sec_label(self,parent,text):
            tk.Label(parent, text=text, font=self.f_label, bg=BG, fg=FG_FAINT).pack(anchor="w", pady=(0,7))
        def _sec_label_inline(self,parent,text):
            tk.Label(parent, text=text, font=self.f_label, bg=BG, fg=FG_FAINT).pack(side="left")

        def _build_card(self,parent,svc,col):
            card=tk.Frame(parent, bg=BG_CARD, highlightbackground=BORDER, highlightthickness=1, bd=0, height=115)
            card.grid(row=0, column=col, padx=5, pady=0, sticky="nsew")
            card.grid_propagate(False)
            short=svc.replace("spyguard-","").title()
            top_bar=tk.Frame(card, bg=STATUS_IDLE, height=3); top_bar.place(x=0,y=0,relwidth=1.0)
            led=PulsingLED(card, size=12, bg=BG_CARD); led.canvas.place(x=14,y=16)
            tk.Label(card, text=short, font=self.f_svc, bg=BG_CARD, fg=FG).place(x=34,y=12)
            tk.Label(card, text=svc, font=("Helvetica",7), bg=BG_CARD, fg=FG_FAINT).place(x=34,y=32)
            state_lbl=tk.Label(card, text="INACTIVO", font=("Helvetica",8,"bold"), bg=BG_CARD, fg=FG_DIM); state_lbl.place(x=14,y=56)
            uptime_lbl=tk.Label(card, text="", font=("Helvetica",7), bg=BG_CARD, fg=FG_FAINT); uptime_lbl.place(x=14,y=75)
            rb=tk.Label(card, text="\u21bb", font=("Helvetica",13), bg=BG_CARD, fg=FG_FAINT, cursor="hand2"); rb.place(x=175,y=12)
            rb.bind("<Button-1>", lambda e,s=svc: self.restart_service(s))
            rb.bind("<Enter>", lambda e,b=rb: b.config(fg=FG))
            rb.bind("<Leave>", lambda e,b=rb: b.config(fg=FG_FAINT))
            Tooltip(rb, f"Reiniciar {svc}")
            self.service_cards[svc]={"led":led,"state_label":state_lbl,"uptime_label":uptime_lbl,"top_bar":top_bar}

        def _update_clock(self):
            self.clock_label.config(text=time.strftime("%H:%M:%S")); self.root.after(1000, self._update_clock)
        def _tick_uptime(self):
            for svc in SERVICES:
                if self._uptime_active.get(svc):
                    self._uptime[svc]+=1; card=self.service_cards.get(svc)
                    if card:
                        up=self._uptime[svc]; h,rem=divmod(up,3600); m,s=divmod(rem,60)
                        txt=f"up {h:02d}:{m:02d}:{s:02d}" if h else f"up {m:02d}:{s:02d}"
                        card["uptime_label"].config(text=txt)
            self.root.after(1000, self._tick_uptime)

        def log(self,text,tag="info"):
            def _do():
                self.console.configure(state="normal")
                self.console.insert("end", f" {time.strftime('%H:%M:%S')} ", ("ts",))
                self.console.insert("end", f"{text}\n", (tag,)); self.console.see("end")
                self.console.configure(state="disabled")
            self.root.after(0, _do)

        def _clear_logs(self):
            self.console.configure(state="normal"); self.console.delete("1.0","end")
            self.console.configure(state="disabled"); self.log("Consola limpiada", "info")

        def run_cmd(self, cmd, shell=False, timeout=30):
            try:
                kw=dict(capture_output=True, text=True, timeout=timeout)
                r=subprocess.run(cmd, shell=shell, **kw)
                return r.returncode==0, r.stdout, r.stderr
            except subprocess.TimeoutExpired:
                return False, "", f"Timeout ({timeout}s)"
            except Exception as e:
                return False, "", str(e)

        def _wait_for_port(self,host,port,timeout=30):
            start=time.time(); self.log(f"  Health check {host}:{port} ...", "info")
            while time.time()-start<timeout:
                try:
                    with socket.create_connection((host,port), timeout=2):
                        self.log(f"  Puerto {port} abierto", "ok"); return True
                except: pass
                time.sleep(0.5)
            self.log(f"  Puerto {port} no respondio tras {timeout}s", "err"); return False

        def get_service_state(self,svc):
            _,out_a,_=self.run_cmd(["systemctl","show",svc,"--property=ActiveState","--value"])
            active=out_a.strip().split("\n")[0].strip() if out_a.strip() else ""
            _,out_s,_=self.run_cmd(["systemctl","show",svc,"--property=SubState","--value"])
            sub=out_s.strip().split("\n")[0].strip() if out_s.strip() else ""
            if not active or active=="unknown":
                _,out3,_=self.run_cmd(["systemctl","is-active",svc])
                active=out3.strip() or "inactive"; sub="running" if active=="active" else "dead"
            return active,sub

        def wait_for_service(self,svc,timeout=30,stable_time=2):
            start=time.time(); running_since=None
            while time.time()-start<timeout:
                active,sub=self.get_service_state(svc)
                if active=="active" and sub=="running":
                    if running_since is None: running_since=time.time()
                    elif time.time()-running_since>=stable_time: return True,active,sub
                else: running_since=None
                time.sleep(0.5)
            active,sub=self.get_service_state(svc); return False,active,sub

        def _show_service_logs(self,svc,lines=25):
            ok,out,_=self.run_cmd(["journalctl","-u",svc,"--no-pager","-n",str(lines)])
            if ok and out:
                self.log(f"--- Diagnostico: {svc} ---", "warn")
                for line in out.strip().split("\n"):
                    if line.strip(): self.log(f"  {line.strip()}", "err")
            else: self.log(f"No se pudieron obtener logs de {svc}", "err")

        def check_status(self):
            active_count=0; all_active=True
            for svc in SERVICES:
                active,sub=self.get_service_state(svc); card=self.service_cards[svc]; was_active=self._uptime_active.get(svc,False)
                if active=="active" and sub in ("running","exited"):
                    card["led"].set_state(STATUS_OK, pulsing=True); card["state_label"].config(text="ACTIVO", fg=STATUS_OK); card["top_bar"].config(bg=STATUS_OK)
                    self._uptime_active[svc]=True; active_count+=1
                elif active=="activating" and sub in ("activating","start-pre","start"):
                    card["led"].set_state(STATUS_WARN, pulsing=True); card["state_label"].config(text="INICIANDO", fg=STATUS_WARN); card["top_bar"].config(bg=STATUS_WARN)
                    self._uptime_active[svc]=False; all_active=False
                elif sub=="auto-restart" or (active=="failed"):
                    card["led"].set_state(STATUS_ERR, pulsing=False)
                    card["state_label"].config(text="FALLIDO" if active=="failed" else "REINICIANDO", fg=STATUS_ERR); card["top_bar"].config(bg=STATUS_ERR)
                    self._uptime_active[svc]=False; self._uptime[svc]=0; all_active=False
                else:
                    card["led"].set_state(STATUS_IDLE, pulsing=False); card["state_label"].config(text="INACTIVO", fg=FG_DIM); card["top_bar"].config(bg=STATUS_IDLE)
                    if was_active: self._uptime[svc]=0
                    self._uptime_active[svc]=False; all_active=False

            if all_active and active_count==len(SERVICES):
                self.status_led.set_state(STATUS_OK, pulsing=True); self.status_text.config(text="SpyGuard operativo", fg=STATUS_OK); self.status_detail.config(text="Todos los servicios activos y corriendo")
            elif active_count==0:
                self.status_led.set_state(STATUS_IDLE, pulsing=False); self.status_text.config(text="SpyGuard detenido", fg=FG); self.status_detail.config(text="Ningun servicio activo")
            else:
                self.status_led.set_state(STATUS_WARN, pulsing=True); self.status_text.config(text="SpyGuard parcialmente activo", fg=STATUS_WARN); self.status_detail.config(text=f"{active_count} de {len(SERVICES)} servicios activos")
            return all_active, active_count

        def auto_refresh(self): self.check_status(); self.root.after(5000, self.auto_refresh)

        def _copy_certs(self):
            self.log("Copiando certificados SSL...", "warn")
            for fname in ("cert.pem","key.pem"):
                src=os.path.join(CERT_SRC,fname); dst=os.path.join(CERT_DST,fname)
                if os.path.exists(src):
                    try: shutil.copy2(src,dst); self.log(f"  {fname} -> OK", "ok")
                    except Exception as ex: self.log(f"  {fname} -> Error: {ex}", "err")
                else: self.log(f"  {fname} no encontrado en origen", "warn")

        def start_all(self):
            def task():
                self._set_btns("disabled"); self.progress_var.set(0)
                self.log("--- INICIANDO SECUENCIA DE ARRANQUE ---", "warn"); self._copy_certs(); self.progress_var.set(5)
                svc="spyguard-backend"; self.log(f"$ systemctl start {svc}", "cmd"); self.run_cmd(["systemctl","start",svc]); self.progress_var.set(15)
                self.log(f"Esperando estabilizacion de {svc}...", "info")
                ok,active,sub=self.wait_for_service(svc,timeout=30,stable_time=2)
                if not ok:
                    self.log(f"ERROR: {svc} no se estabilizo ({active}/{sub})", "err"); self._show_service_logs(svc,lines=20); self._set_btns("normal"); self.progress_var.set(0); self._notify("SpyGuard Error", f"{svc} no arranco correctamente", urgent=True); return
                self.log(f"  {svc} [{sub.upper()}] OK", "ok"); self.progress_var.set(25)
                if not self._wait_for_port("localhost",8443,timeout=30):
                    self.log("ERROR: Backend no acepta conexiones de red", "err"); self._show_service_logs(svc,lines=20); self._set_btns("normal"); self.progress_var.set(0); self._notify("SpyGuard Error", "Backend activo pero no responde en puerto 8443", urgent=True); return
                self.progress_var.set(35)
                svc="spyguard-frontend"; self.log(f"$ systemctl start {svc}", "cmd"); self.run_cmd(["systemctl","start",svc])
                ok,active,sub=self.wait_for_service(svc,timeout=20,stable_time=1)
                if ok: self.log(f"  {svc} [{sub.upper()}] OK", "ok")
                else: self.log(f"  ADVERTENCIA: {svc} no estable ({active}/{sub})", "warn")
                self.progress_var.set(55)
                svc="spyguard-watchers"; self.log(f"$ systemctl start {svc}", "cmd"); self.run_cmd(["systemctl","start",svc]); time.sleep(2); self.progress_var.set(65)
                self.log(f"Esperando estabilizacion de {svc} (intento 1)...", "info")
                ok,active,sub=self.wait_for_service(svc,timeout=40,stable_time=3)
                if not ok:
                    self.log(f"  Primer intento fallido ({active}/{sub}). Reintentando en 5s...", "warn"); self._show_service_logs(svc,lines=10); time.sleep(5); self.run_cmd(["systemctl","start",svc]); ok,active,sub=self.wait_for_service(svc,timeout=40,stable_time=3)
                if not ok:
                    self.log(f"ERROR: {svc} no se estabilizo tras reintento ({active}/{sub})", "err"); self._show_service_logs(svc,lines=30); self.progress_var.set(0); self._set_btns("normal"); self.check_status(); self._notify("SpyGuard Alerta", f"{svc} se encendio pero no se mantuvo activo", urgent=True); return
                self.log(f"  {svc} [{sub.upper()}] OK", "ok"); self.progress_var.set(100); time.sleep(0.4); self.progress_var.set(0)
                all_ok,count=self.check_status(); self._set_btns("normal")
                if all_ok:
                    self._notify("SpyGuard Online", "Todos los servicios estan activos y estables"); self.log(f"Frontend: {FRONTEND_URL}", "ok"); self.log(f"Backend:  {BACKEND_URL}", "ok")
                else: self._notify("SpyGuard Alerta", f"Solo {count}/{len(SERVICES)} servicios activos", urgent=True)
            threading.Thread(target=task, daemon=True).start()

        def stop_all(self):
            def task():
                self._set_btns("disabled"); self.progress_var.set(0); self.log("--- DETENIENDO TODOS LOS SERVICIOS ---", "warn"); total=len(SERVICES)
                for i,svc in enumerate(reversed(SERVICES)):
                    self.progress_var.set(((i+1)/total)*100); self.log(f"$ systemctl stop {svc}", "cmd"); ok,out,err=self.run_cmd(["systemctl","stop",svc])
                    if ok: self.log(f"  {svc} detenido", "ok")
                    else: self.log(f"  {svc} {err or out or 'sin respuesta'}", "err")
                    time.sleep(0.4)
                self.progress_var.set(0); self.check_status(); self._set_btns("normal"); self._notify("SpyGuard Offline", "Todos los servicios han sido detenidos")
            threading.Thread(target=task, daemon=True).start()

        def restart_service(self,svc):
            def task():
                self.log(f"Reiniciando {svc}...", "warn"); ok,out,err=self.run_cmd(["systemctl","restart",svc])
                if not ok: self.log(f"  restart: {err or out}", "err")
                stable_time=3 if svc=="spyguard-watchers" else 2
                ok,active,sub=self.wait_for_service(svc,timeout=30,stable_time=stable_time)
                if ok: self.log(f"{svc} reiniciado OK ({sub})", "ok"); self._uptime[svc]=0
                else: self.log(f"Error reiniciando {svc}: {active}/{sub}", "err"); self._show_service_logs(svc,lines=20)
                self.check_status()
            threading.Thread(target=task, daemon=True).start()

        def open_url(self, url):
            self.log(f"Abriendo: {url}", "info")
            self.log(f"  GUI_USER resuelto: {GUI_USER}", "info")
            env_pairs = _gui_env_pairs()
            self.log(f"  Env display: {' '.join(env_pairs)}", "info")

            # Buscar el binario del navegador (chromium es el estándar en Debian)
            browser_path = None
            browser_name = None
            for candidate in ["chromium", "chromium-browser", "google-chrome", "firefox"]:
                # shutil.which busca en PATH del proceso root; también comprobamos rutas fijas
                path = shutil.which(candidate)
                if not path:
                    for fixed in (f"/usr/bin/{candidate}", f"/usr/local/bin/{candidate}",
                                  f"/snap/bin/{candidate}"):
                        if os.path.isfile(fixed):
                            path = fixed
                            break
                if path:
                    browser_path = path
                    browser_name = candidate
                    break

            if browser_path:
                # Popen: lanzar y NO esperar (los navegadores son procesos persistentes)
                cmd = ["sudo", "-u", GUI_USER, "env"] + env_pairs + [browser_path, "--new-window", url]
                self.log(f"  CMD: {' '.join(cmd)}", "info")
                try:
                    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     start_new_session=True)
                    self.log(f"Lanzado: {browser_name}", "ok")
                    return
                except Exception as ex:
                    self.log(f"  Error lanzando {browser_name}: {ex}", "err")

            # Fallback: xdg-open también con Popen
            try:
                subprocess.Popen(
                    ["sudo", "-u", GUI_USER, "env"] + env_pairs + ["xdg-open", url],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True)
                self.log("Lanzado via xdg-open", "ok")
                return
            except Exception as ex:
                self.log(f"  xdg-open falló: {ex}", "err")

            self.log("No se detectó navegador gráfico", "err")
            messagebox.showwarning("Sin navegador", f"Accede manualmente a:\n{url}")

        def _set_btns(self,state):
            for b in self.buttons: b.config(state=state)

        def _notify(self, title, message, urgent=False):
            # CORRECCIÓN: notify-send como el usuario de sesión con DBUS/DISPLAY correctos
            try:
                env_pairs = _gui_env_pairs()
                cmd = (["sudo", "-u", GUI_USER, "env"] + env_pairs +
                       ["notify-send",
                        "-u", "critical" if urgent else "normal",
                        "-i", "dialog-error" if urgent else "dialog-information",
                        "SpyGuard", f"<b>{title}</b>\n{message}"])
                subprocess.run(cmd, capture_output=True, timeout=5)
            except:
                pass

        def on_close(self): self.log("Cerrando panel...", "info"); self.root.destroy()


    def check_root():
        """
        Si no somos root, relanzamos el script con pkexec o sudo
        pasando explícitamente las variables de entorno gráfico.
        CORRECCIÓN: pkexec/sudo en Debian 13 NO heredan DISPLAY, WAYLAND_DISPLAY, etc.
        """
        if os.geteuid() != 0:
            script = os.path.abspath(__file__)
            env_pairs = _gui_env_pairs()
            base_cmd = [sys.executable, script] + sys.argv[1:]

            # Intentar pkexec primero (muestra diálogo gráfico de contraseña)
            if shutil.which("pkexec"):
                r = subprocess.run(["pkexec", "env"] + env_pairs + base_cmd)
                if r.returncode == 0:
                    sys.exit(0)

            # Fallback: sudo (requiere terminal o askpass configurado)
            r = subprocess.run(["sudo", "env"] + env_pairs + base_cmd)
            sys.exit(r.returncode)


    if __name__ == "__main__":
        if os.geteuid() != 0:
            print("[SpyGuard] Se requieren privilegios de administrador.")
            check_root()
        root = tk.Tk()
        app = SpyGuardGUI(root)
        root.mainloop()

except Exception as e:
    err_msg = f"CRASH: {e}\n{traceback.format_exc()}"
    _log_crash(err_msg)
    print(err_msg)
    try:
        import tkinter as tk
        from tkinter import messagebox
        root = tk.Tk(); root.withdraw()
        messagebox.showerror("SpyGuard Error", f"No se pudo iniciar el panel:\n\n{e}\n\nRevisa: {_LOG_FILE}")
    except:
        pass
    sys.exit(1)
