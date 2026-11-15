"""
Buckshot Helper - an always-on-top "cheat window" for Buckshot Roulette.

It does NOT read or modify the game. You type in what the game tells you
(shell counts at each load, magnifier / burner phone / beer reveals, every
shot fired) and it tracks the chamber, shows the exact odds for every shell,
and tells you who to shoot.

Run:  python buckshot_helper.py      (needs Python 3.8+ with tkinter)

Keyboard shortcuts (window focused):
  L / B      current shell fired (or racked with beer) was LIVE / BLANK
  Q / W      magnifier showed LIVE / BLANK
  I          inverter used on current shell
  Ctrl+Z     undo
  Ctrl+N     new load (uses the live / blank boxes)
"""

import copy

LIVE, BLANK = "L", "B"


def flip(t):
    return BLANK if t == LIVE else LIVE


class Chamber:
    """Pure game-state tracker (no GUI) so it can be tested on its own.

    Shell types are stored as they were LOADED. The inverter only changes how
    the current shell comes out, so it is tracked as a flag on slot 0.
    """

    def __init__(self):
        self.live = 0
        self.blank = 0
        self.known = {}      # slot index (0 = current) -> LIVE / BLANK (as loaded)
        self.inverted = False
        self.log = []
        self._undo = []

    # ----- helpers -------------------------------------------------------
    @property
    def total(self):
        return self.live + self.blank

    def _snapshot(self):
        self._undo.append(copy.deepcopy((self.live, self.blank, self.known,
                                         self.inverted, self.log)))
        del self._undo[:-200]

    def undo(self):
        if not self._undo:
            return False
        self.live, self.blank, self.known, self.inverted, self.log = self._undo.pop()
        return True

    def _check(self):
        kl = sum(1 for v in self.known.values() if v == LIVE)
        kb = len(self.known) - kl
        if kl > self.live or kb > self.blank:
            raise ValueError("That contradicts the shell count. Check your inputs or undo.")

    # ----- odds ----------------------------------------------------------
    def p_live_loaded(self, i):
        """Chance slot i was loaded live."""
        if i in self.known:
            return 1.0 if self.known[i] == LIVE else 0.0
        unknown_total = self.total - len(self.known)
        unknown_live = self.live - sum(1 for v in self.known.values() if v == LIVE)
        return unknown_live / unknown_total if unknown_total else 0.0

    def p_live(self, i):
        """Chance slot i comes out live (inverter applied to slot 0)."""
        p = self.p_live_loaded(i)
        return 1.0 - p if (i == 0 and self.inverted) else p

    def recommendation(self):
        if self.total == 0:
            return "Gun is empty - enter the next load.", "neutral"
        p = self.p_live(0)
        if p >= 1.0:
            return "LIVE for sure -> shoot the DEALER (handsaw = 2 dmg)", "live"
        if p <= 0.0:
            tip = " or invert it and shoot the dealer" if not self.inverted else ""
            return f"BLANK for sure -> shoot YOURSELF for a free turn{tip}", "blank"
        pct = round(p * 100)
        if p > 0.5:
            return f"{pct}% live -> shoot the DEALER", "live"
        if p < 0.5:
            return f"{pct}% live -> shoot YOURSELF", "blank"
        return "50/50 -> use magnifier / beer / phone if you have one, else shoot the DEALER", "neutral"

    # ----- actions -------------------------------------------------------
    def new_load(self, live, blank):
        if live < 0 or blank < 0 or live + blank == 0:
            raise ValueError("Enter at least one shell.")
        self._snapshot()
        self.live, self.blank = live, blank
        self.known, self.inverted = {}, False
        self.log.append(f"--- New load: {live} live, {blank} blank ---")

    def shell_out(self, seen, how="Fired"):
        """Current shell left the gun (shot or racked with beer) and was `seen`."""
        if self.total == 0:
            raise ValueError("Gun is empty.")
        loaded = flip(seen) if self.inverted else seen
        if loaded == LIVE and self.live == 0 or loaded == BLANK and self.blank == 0:
            raise ValueError("No shells of that type left. Check your inputs or undo.")
        self._snapshot()
        if loaded == LIVE:
            self.live -= 1
        else:
            self.blank -= 1
        self.known = {i - 1: t for i, t in self.known.items() if i > 0}
        self.inverted = False
        self.log.append(f"{how}: {'LIVE' if seen == LIVE else 'blank'}"
                        f"  ({self.live} live / {self.blank} blank left)")

    def magnifier(self, seen):
        if self.total == 0:
            raise ValueError("Gun is empty.")
        self._snapshot()
        self.known[0] = flip(seen) if self.inverted else seen
        try:
            self._check()
        except ValueError:
            self.undo()
            raise
        self.log.append(f"Magnifier: current is {'LIVE' if seen == LIVE else 'blank'}")

    def phone(self, position, t):
        """Burner phone: `position` is 1-based ("second shell" = 2)."""
        idx = position - 1
        if not 0 <= idx < self.total:
            raise ValueError(f"Only {self.total} shells left in the gun.")
        self._snapshot()
        self.known[idx] = t
        try:
            self._check()
        except ValueError:
            self.undo()
            raise
        self.log.append(f"Phone: shell #{position} is {'LIVE' if t == LIVE else 'blank'}")

    def invert(self):
        if self.total == 0:
            raise ValueError("Gun is empty.")
        self._snapshot()
        self.inverted = not self.inverted
        self.log.append("Inverter used on current shell")


# ======================================================================
# GUI
# ======================================================================
def run_gui():
    import tkinter as tk
    from tkinter import messagebox

    BG, PANEL, FG, DIM = "#141414", "#1f1f1f", "#e8e2d0", "#8a8578"
    RED, BLUE, AMBER = "#c0392b", "#2e6fbf", "#c9a227"

    st = Chamber()
    root = tk.Tk()
    root.title("Buckshot Helper")
    root.configure(bg=BG)
    root.attributes("-topmost", True)
    root.resizable(False, False)

    def btn(parent, text, cmd, color=PANEL, width=None):
        b = tk.Button(parent, text=text, command=cmd, bg=color, fg=FG,
                      activebackground=color, activeforeground="white",
                      relief="flat", bd=0, padx=8, pady=5,
                      font=("Segoe UI", 10, "bold"), cursor="hand2")
        if width:
            b.config(width=width)
        return b

    def lbl(parent, text="", size=10, color=FG, bold=False):
        return tk.Label(parent, text=text, bg=parent["bg"], fg=color,
                        font=("Segoe UI", size, "bold" if bold else "normal"))

    def act(fn, *a):
        try:
            fn(*a)
        except ValueError as e:
            messagebox.showwarning("Buckshot Helper", str(e), parent=root)
        refresh()

    # --- load row ---
    f_load = tk.Frame(root, bg=BG, padx=10, pady=8)
    f_load.pack(fill="x")
    lbl(f_load, "Load:", bold=True).pack(side="left")
    v_live, v_blank = tk.IntVar(value=2), tk.IntVar(value=2)
    for var, name, col in ((v_live, "live", RED), (v_blank, "blank", BLUE)):
        tk.Spinbox(f_load, from_=0, to=8, width=3, textvariable=var,
                   bg=PANEL, fg=FG, buttonbackground=PANEL, relief="flat",
                   insertbackground=FG, font=("Segoe UI", 11)).pack(side="left", padx=(8, 2))
        lbl(f_load, name, color=col, bold=True).pack(side="left")
    btn(f_load, "New load", lambda: act(st.new_load, v_live.get(), v_blank.get()),
        AMBER).pack(side="right")

    # --- status ---
    f_stat = tk.Frame(root, bg=PANEL, padx=10, pady=8)
    f_stat.pack(fill="x", padx=10)
    l_counts = lbl(f_stat, size=12, bold=True)
    l_counts.pack(anchor="w")
    l_odds = lbl(f_stat, size=26, bold=True)
    l_odds.pack(anchor="w")
    l_rec = tk.Label(f_stat, bg=PANEL, fg=FG, font=("Segoe UI", 11, "bold"),
                     wraplength=380, justify="left")
    l_rec.pack(anchor="w")
    f_slots = tk.Frame(f_stat, bg=PANEL, pady=6)
    f_slots.pack(anchor="w")

    # --- action buttons ---
    def section(title):
        f = tk.Frame(root, bg=BG, padx=10, pady=4)
        f.pack(fill="x")
        lbl(f, title, size=9, color=DIM).pack(anchor="w")
        row = tk.Frame(f, bg=BG)
        row.pack(fill="x")
        return row

    r = section("Shot fired  (L / B)")
    btn(r, "LIVE", lambda: act(st.shell_out, LIVE), RED, 11).pack(side="left", padx=(0, 6))
    btn(r, "BLANK", lambda: act(st.shell_out, BLANK), BLUE, 11).pack(side="left")

    r = section("Beer racked out")
    btn(r, "LIVE", lambda: act(st.shell_out, LIVE, "Beer"), RED, 11).pack(side="left", padx=(0, 6))
    btn(r, "BLANK", lambda: act(st.shell_out, BLANK, "Beer"), BLUE, 11).pack(side="left")

    r = section("Magnifying glass  (Q / W)")
    btn(r, "LIVE", lambda: act(st.magnifier, LIVE), RED, 11).pack(side="left", padx=(0, 6))
    btn(r, "BLANK", lambda: act(st.magnifier, BLANK), BLUE, 11).pack(side="left")

    r = section("Burner phone  (shell #, counting current as 1)")
    v_pos = tk.IntVar(value=2)
    tk.Spinbox(r, from_=1, to=8, width=3, textvariable=v_pos, bg=PANEL, fg=FG,
               buttonbackground=PANEL, relief="flat", insertbackground=FG,
               font=("Segoe UI", 11)).pack(side="left", padx=(0, 6))
    btn(r, "LIVE", lambda: act(st.phone, v_pos.get(), LIVE), RED, 8).pack(side="left", padx=(0, 6))
    btn(r, "BLANK", lambda: act(st.phone, v_pos.get(), BLANK), BLUE, 8).pack(side="left")

    r = section("Other")
    btn(r, "Inverter (I)", lambda: act(st.invert)).pack(side="left", padx=(0, 6))
    btn(r, "Undo (Ctrl+Z)", lambda: act(st.undo)).pack(side="left", padx=(0, 6))
    v_top = tk.BooleanVar(value=True)
    tk.Checkbutton(r, text="On top", variable=v_top, bg=BG, fg=FG, selectcolor=PANEL,
                   activebackground=BG, activeforeground=FG,
                   command=lambda: root.attributes("-topmost", v_top.get())).pack(side="left")
    v_alpha = tk.DoubleVar(value=1.0)
    tk.Scale(r, from_=0.4, to=1.0, resolution=0.05, orient="horizontal", showvalue=False,
             variable=v_alpha, length=70, bg=BG, troughcolor=PANEL, highlightthickness=0,
             command=lambda _v: root.attributes("-alpha", v_alpha.get())).pack(side="right")
    lbl(r, "opacity", size=8, color=DIM).pack(side="right")

    # --- log ---
    t_log = tk.Text(root, height=6, width=52, bg=PANEL, fg=DIM, relief="flat",
                    font=("Consolas", 9), state="disabled")
    t_log.pack(padx=10, pady=(4, 10))

    def refresh():
        if st.total == 0:
            l_counts.config(text="Enter the shell count shown at the start of the load")
            l_odds.config(text="--", fg=DIM)
        else:
            inv = "   [INVERTED]" if st.inverted else ""
            l_counts.config(text=f"{st.live} live  /  {st.blank} blank  left{inv}")
            p = st.p_live(0)
            l_odds.config(text=f"{round(p * 100)}% live",
                          fg=RED if p > 0.5 else BLUE if p < 0.5 else AMBER)
        text, kind = st.recommendation()
        l_rec.config(text=text, fg={"live": RED, "blank": BLUE}.get(kind, AMBER))

        for w in f_slots.winfo_children():
            w.destroy()
        for i in range(st.total):
            p = st.p_live(i)
            col = RED if p == 1 else BLUE if p == 0 else "#3a3a3a"
            txt = "LIVE" if p == 1 else "BLNK" if p == 0 else f"{round(p * 100)}%"
            cell = tk.Frame(f_slots, bg=PANEL)
            cell.pack(side="left", padx=2)
            tk.Label(cell, text=txt, bg=col, fg="white", width=5,
                     font=("Segoe UI", 9, "bold"),
                     relief="solid" if i == 0 else "flat", bd=2 if i == 0 else 0).pack()
            tk.Label(cell, text="now" if i == 0 else f"#{i + 1}", bg=PANEL, fg=DIM,
                     font=("Segoe UI", 8)).pack()

        t_log.config(state="normal")
        t_log.delete("1.0", "end")
        t_log.insert("end", "\n".join(st.log[-50:]))
        t_log.see("end")
        t_log.config(state="disabled")

    keys = {
        "l": lambda: act(st.shell_out, LIVE), "b": lambda: act(st.shell_out, BLANK),
        "q": lambda: act(st.magnifier, LIVE), "w": lambda: act(st.magnifier, BLANK),
        "i": lambda: act(st.invert),
    }

    def on_key(e):
        if isinstance(e.widget, tk.Spinbox):
            return
        f = keys.get(e.keysym.lower())
        if f:
            f()

    root.bind("<Key>", on_key)
    root.bind("<Control-z>", lambda e: act(st.undo))
    root.bind("<Control-n>", lambda e: act(st.new_load, v_live.get(), v_blank.get()))

    refresh()
    root.mainloop()


if __name__ == "__main__":
    run_gui()
