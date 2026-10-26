# dmgbuild settings for Payroof.dmg; see apple/make-dmg.sh.
# Icon positions match the diagram drawn by apple/generate-dmg-background.swift.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild injects `defines`)
background = defines["background"]  # noqa: F821

format = "ULFO"  # LZFSE, readable on every macOS the app supports
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {os.path.basename(app): (165, 185), "Applications": (495, 185)}

window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
arrange_by = None
